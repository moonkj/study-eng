import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/app.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/audio/tts.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/grade_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/data/toeic.dart';
import 'package:todaye/domain/toeic_feedback.dart';
import 'package:todaye/features/speaking/speech_input.dart';

import '../domain/reminder_test.dart' show FakeReminder;
import '../support/fixed_fallback.dart';
import '../support/toeic_fixture.dart';
import 'daily_flow_test.dart' show FakeSpeaker, seeded, setPhone;

/// 답하기 시간 동안 [answer] 를 말하고, 시간이 끝나(stop) 최종 결과를 돌려주는 가짜 음성 인식
class ScriptedSpeech implements SpeechInput {
  ScriptedSpeech(this.answer);
  final String Function(String expected) answer;
  Completer<SpeechAttempt>? _pending;
  String _text = '';
  int listens = 0;

  @override
  Future<SpeechAttempt> listen({
    required String expected,
    bool hint = false,
    void Function(String partial)? onPartial,
  }) {
    listens++;
    _text = answer(expected);
    onPartial?.call(_text);
    return (_pending = Completer<SpeechAttempt>()).future;
  }

  @override
  Future<void> stop() async {
    final p = _pending;
    if (p != null && !p.isCompleted) p.complete(SpeechAttempt.heard(_text));
  }
}

/// 테스트가 [say] 로 말을 이어 붙이는 가짜 음성 인식 (말한 시간을 길게 만들 때)
class ManualSpeech implements SpeechInput {
  void Function(String partial)? _onPartial;
  Completer<SpeechAttempt>? _pending;
  String _text = '';

  /// 따라 말하기처럼 문장 하나를 들을 때는 그 문장을 그대로 말한다
  bool echo = false;

  void say(String text) {
    _text = text;
    _onPartial?.call(text);
  }

  @override
  Future<SpeechAttempt> listen({
    required String expected,
    bool hint = false,
    void Function(String partial)? onPartial,
  }) {
    _onPartial = onPartial;
    if (echo) _text = expected;
    return (_pending = Completer<SpeechAttempt>()).future;
  }

  @override
  Future<void> stop() async {
    final p = _pending;
    if (p == null || p.isCompleted) return;
    p.complete(_text.isEmpty ? const SpeechAttempt.failed('없음') : SpeechAttempt.heard(_text));
  }
}

class FakeGrade implements GradeSource {
  FakeGrade({this.points, this.targetMet = true, this.improved = ''});

  /// 유형별 원점수를 따로 줄 때 (없으면 모두 8/10)
  final GradeResult Function(ToeicTaskType task)? points;
  final bool targetMet;
  final String improved;
  final calls = <(ToeicTaskType, String)>[];

  @override
  Future<GradeResult> grade({
    required ToeicTaskType task,
    required String target,
    required String prompt,
    String? reference,
    required String transcript,
    required int seconds,
    required int limitSeconds,
  }) async {
    calls.add((task, target));
    if (points != null) return points!(task);
    return GradeResult(
      score: 8,
      maxScore: 10,
      level: 'IH',
      summaryKo: '전달이 분명해요',
      fixes: const [GradeFix(from: 'a woman drink', to: 'a woman is drinking', whyKo: '진행형')],
      improved: improved,
      targetMet: targetMet,
    );
  }
}

SavedData _seeded({int? target = 140, TodayProgress? today}) {
  final s = seeded();
  return SavedData(
    profile: s.profile,
    contentStep: s.contentStep,
    onboarded: true,
    log: s.log,
    settings: AppSettings(toeicTarget: target),
    today: today,
  );
}

/// 문장 읽기는 원문 그대로, 나머지는 핵심 표현을 넣어 말한다
String _answer(String expected) => expected.startsWith('Welcome') || expected.startsWith('Thank')
    ? expected
    : 'This picture was taken in a cafe because I usually agree';

Widget _app({
  String initial = '/',
  AppStore? store,
  FakeSpeaker? speaker,
  ToeicBank? bank,
  bool noBank = false,
  GradeSource? grade,
  SpeechInput? speech,
}) => ProviderScope(
  overrides: [
    reminderProvider.overrideWithValue(FakeReminder()),
    speakerProvider.overrideWithValue(speaker ?? FakeSpeaker()),
    storeProvider.overrideWithValue(store ?? MemoryStore(_seeded())),
    clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8, 0)),
    speechInputProvider.overrideWithValue(speech ?? ScriptedSpeech(_answer)),
    fallbackPackProvider.overrideWithValue(fixedSamplePackFor),
    toeicBankProvider.overrideWithValue(noBank ? null : (bank ?? toeicFixture)),
    gradeSourceProvider.overrideWithValue(grade),
  ],
  child: TodayeApp(initialLocation: initial),
);

ProviderContainer _c(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<void> _seconds(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('문장 읽기: 시작 → 준비 45초 → 답하기 45초(받아 적기) → 결과', (tester) async {
    await setPhone(tester);
    final speaker = FakeSpeaker();
    await tester.pumpWidget(_app(initial: '/toeic-today', speaker: speaker));
    await tester.pumpAndSettle();

    expect(find.text('Q1 문장 읽기'), findsOneWidget);
    expect(find.text('Welcome to City Library. We are open from nine to six.'), findsOneWidget);
    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump();
    expect(speaker.spoken.last.$1, 'Begin preparing now.');
    expect(find.text('Q1 · 준비 시간'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    await _seconds(tester, 10);
    expect(find.text('35'), findsOneWidget);
    await _seconds(tester, 35);
    await tester.pump();
    expect(speaker.spoken.last.$1, 'Begin speaking now.');
    expect(find.text('Q1 · 답하기'), findsOneWidget);
    // 말하는 중에는 들린 말이 바로 보인다
    expect(find.text('"Welcome to City Library. We are open from nine to six."'), findsOneWidget);
    await _seconds(tester, 45);
    await tester.pumpAndSettle();

    // 요약 띠: 기기 점수(등급은 보이지 않는다) + 고칠 것 1개
    expect(find.text('100점'), findsOneWidget);
    expect(find.text('알아들은 단어 비율로 센 대략의 점수예요'), findsOneWidget);
    expect(find.text('시간이 끝날 때까지 이어서 말해 보세요'), findsOneWidget);
    // 질문 카드는 접혀 있다
    expect(find.text('"Welcome to City Library. We are open from nine to six."'), findsNothing);
    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.text('들린 대로'), findsOneWidget);
    expect(find.text('"Welcome to City Library. We are open from nine to six."'), findsOneWidget);
    expect(find.textContaining('1초 / 45초 동안 말함 · 단어 11개 · 알아들은 단어 100%'), findsOneWidget);
    expect(find.textContaining('원문과'), findsNothing);
    await tester.scrollUntilVisible(find.text('· 쉼표에서 잠깐 쉬어요.'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('· 쉼표에서 잠깐 쉬어요.'), findsOneWidget);
    // 말한 시간이 짧았으므로 다시 말하기가 주 버튼
    expect(find.widgetWithText(FilledButton, '고친 걸로 다시 말하기'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '다음'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    final s = _c(tester).read(studyProvider);
    expect(s.today.toeic['ra-1']!.score, 100);
    expect(s.today.toeic['ra-1']!.graded, isFalse);
    expect(find.text('Q3 사진 묘사'), findsOneWidget);
  });

  testWidgets('사진 묘사(서버 없음): 사진이 없어도 자리 표시, 핵심 표현·모범 답안·오늘 표현을 보여 준다', (tester) async {
    await setPhone(tester);
    final speaker = FakeSpeaker();
    await tester.pumpWidget(
      _app(
        initial: '/toeic-today',
        speaker: speaker,
        store: MemoryStore(
          _seeded(
            today: const TodayProgress(date: '2026-11-22', toeic: {'ra-1': _ra}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Q3 사진 묘사'), findsOneWidget);
    expect(find.text('써 보면 좋은 표현'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump();
    // 연습에서는 준비를 일찍 끝내고, 다 말하면 일찍 끝낼 수 있다
    await tester.tap(find.text('준비 끝 · 바로 말하기'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Q3 · 답하기'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('다 말했어요'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.text('핵심 표현 1/2개 사용'), findsOneWidget);
    expect(find.text('모범 답안'), findsOneWidget);
    expect(find.text('This picture was taken in a cafe. A woman is drinking coffee.'), findsOneWidget);
    expect(find.textContaining('/ 30초 동안 말함'), findsOneWidget);
    final play = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Q3 모범 답안 듣기');
    await tester.ensureVisible(play);
    await tester.pump(); // 스크롤한 위치로 다시 배치한 뒤 누른다
    await tester.tap(play);
    expect(speaker.spoken.last.$1, 'This picture was taken in a cafe. A woman is drinking coffee.');
    expect(find.text('채점하는 중'), findsNothing);
    await tester.scrollUntilVisible(find.text('사진 단어 · sip 홀짝이다'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('사진 단어 · sip 홀짝이다'), findsOneWidget);

    // 고친 걸로 다시 말하기: 같은 문항을 처음부터, 고칠 것을 띄워 둔 채로
    await tester.tap(find.text('고친 걸로 다시 말하기'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Q3 · 준비 시간'), findsOneWidget);
    expect(find.text('이번에 고칠 것'), findsOneWidget);
    expect(find.text('시간이 끝날 때까지 이어서 말해 보세요'), findsOneWidget);
  });

  testWidgets('서버가 있으면 채점 결과를 보여 주고 목표 등급을 보낸다', (tester) async {
    await setPhone(tester);
    final grade = FakeGrade();
    await tester.pumpWidget(
      _app(
        initial: '/toeic-today',
        grade: grade,
        store: MemoryStore(
          _seeded(
            target: 160,
            today: const TodayProgress(date: '2026-11-22', toeic: {'ra-ih': _ra}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Q3 사진 묘사'), findsOneWidget);
    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump();
    await _seconds(tester, 45);
    await tester.pump();
    await _seconds(tester, 30);
    await tester.pumpAndSettle();
    expect(grade.calls.single, (ToeicTaskType.picture, 'IH'));
    // 요약 띠: 점수 · 등급(목표 이상이면 체크) · 목표 대비 · 고칠 것 1개
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('IH'), findsWidgets);
    expect(find.text('목표 IH 수준'), findsOneWidget);
    expect(find.textContaining('a woman is drinking', findRichText: true), findsOneWidget);
    expect(find.text('진행형'), findsOneWidget);
    // 채점 세부는 카드를 펼쳐야 보인다
    expect(find.text('전달이 분명해요'), findsNothing);
    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.text('전달이 분명해요'), findsOneWidget);
    expect(find.text('채점 8/10'), findsOneWidget);
    // IH 목표: IH 모범 답안 (카드 + 따라 하기)
    expect(find.text('This photo shows an open-plan office.'), findsWidgets);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    final r = _c(tester).read(studyProvider).today.toeic['pic-ih']!;
    expect(r.graded, isTrue);
    expect(r.score, 80);
  });

  testWidgets('목표를 고르지 않았으면 첫 토스 말하기에서 한 번 묻는다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app(initial: '/toeic-today', store: MemoryStore(_seeded(target: null))));
    await tester.pumpAndSettle();
    expect(find.text('목표 점수를 골라요'), findsOneWidget);
    expect(find.text('공식 구간 140-150'), findsOneWidget);
    await tester.tap(find.text('160점 · IH'));
    await tester.pump();
    await tester.tap(find.text('IH 목표로 시작'));
    await tester.pumpAndSettle();
    final s = _c(tester).read(studyProvider);
    expect(s.settings.toeicTarget, 160);
    expect(s.contentStep, 9);
    expect(find.text('Q1 문장 읽기'), findsOneWidget);
    expect(find.text('Attention, passengers. The train to Boston has been delayed.'), findsOneWidget);
  });

  testWidgets('문항 모음이 없으면 말하기 단계는 예전 따라 말하기', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app(initial: '/', noBank: true));
    await tester.pumpAndSettle();
    expect(find.text('예문 따라 말하기'), findsOneWidget);
    expect(find.text('토스 실전 모의고사'), findsNothing);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(_app(initial: '/toeic-today', noBank: true));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('말하기 시작'), findsOneWidget);
  });

  testWidgets('루틴: 홈의 토스 말하기 → 세 문항을 마치면 말하기 단계 완료, 결과가 저장된다', (tester) async {
    await setPhone(tester);
    final store = MemoryStore(
      _seeded(
        today: const TodayProgress(date: '2026-11-22', done: {'expressions', 'words'}),
      ),
    );
    await tester.pumpWidget(_app(store: store));
    await tester.pumpAndSettle();
    expect(find.text('토스 말하기'), findsOneWidget);
    expect(find.textContaining('문장 읽기 · 사진 묘사 · 질문 답하기'), findsNothing); // 지금 단계라 부제 대신 진행 표시
    await tester.tap(find.text('토스 말하기'));
    await tester.pumpAndSettle();

    for (final title in ['Q1 문장 읽기', 'Q3 사진 묘사', 'Q5-7 질문에 답하기']) {
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.text('시작'));
      final turns = title.startsWith('Q5') ? 3 : 1;
      for (var t = 0; t < turns; t++) {
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('준비 끝 · 바로 말하기'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text('다 말했어요'));
        await tester.pump();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      if (title.startsWith('Q5')) {
        // 실제 시험처럼 질문은 화면에도 나왔고, 결과에서 질문별로 다시 본다
        expect(find.text('How often do you watch movies?'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Q7').first, 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Q7'), findsWidgets);
      }
      await tester.scrollUntilVisible(find.text('다음'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }

    expect(find.text('말하기 완료!'), findsOneWidget);
    final s = _c(tester).read(studyProvider);
    expect(s.done.contains(RoutineStep.speaking), isTrue);
    expect(s.today.toeic.keys.toSet(), {'ra-1', 'pic-1', 'q-1'});
    expect(store.load()!.today!.toeic.length, 3);
  });

  testWidgets('모의고사: 11문항을 시험 시간대로 끝까지, 중간 피드백 없이 → 결과 요약과 기록', (tester) async {
    await setPhone(tester);
    final speaker = FakeSpeaker();
    // Q1~Q10 3/3, Q11 3/5 → 가중 비율 (17 + 4×0.6)/21 ≈ 92 → IH 칸 위쪽 절반 → "IH~AL"
    final grade = FakeGrade(
      points: (task) =>
          GradeResult(score: 3, maxScore: task == ToeicTaskType.opinion ? 5 : 3, level: 'IH', summaryKo: '좋아요'),
    );
    await tester.pumpWidget(_app(initial: '/toeic-mock', speaker: speaker, grade: grade));
    await tester.pumpAndSettle();
    expect(find.text('실제 시험처럼 11문항'), findsOneWidget);
    await tester.tap(find.text('모의고사 시작'));
    await tester.pump();
    expect(find.text('Q1 문장 읽기'), findsOneWidget);
    await tester.tap(find.text('시작'));

    var seen = <String>{};
    for (var i = 0; i < 900 && find.text('예상 등급').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
      for (final t in ['Q2 문장 읽기', 'Q4 사진 묘사', 'Q8-10 표 보고 답하기', 'Q11 의견 말하기']) {
        if (find.text(t).evaluate().isNotEmpty) seen.add(t);
      }
      // 문항 사이에 결과·피드백은 나오지 않는다
      expect(find.text('모범 답안'), findsNothing);
    }
    await tester.pumpAndSettle();
    expect(seen.length, 4);
    expect(find.text('예상 등급'), findsOneWidget);
    expect(find.text('IH~AL'), findsOneWidget); // 한 등급이 아니라 범위로
    expect(find.text('목표 IM3 달성!'), findsOneWidget);
    // 표 질문은 듣기로만: 소리로 읽어 줬다
    expect(speaker.spoken.map((e) => e.$1), contains('Where is the workshop?'));
    expect(speaker.spoken.where((e) => e.$1 == 'What sessions are in the morning?').length, 2);
    expect(grade.calls.length, 11);

    final s = _c(tester).read(studyProvider);
    final m = s.mocks.single;
    expect(m.scores.length, 11);
    expect(m.scores.take(10).every((e) => e == 100), isTrue);
    expect(m.points, [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]);
    expect(m.level, 'IH~AL');
    expect(m.graded, isTrue);
    expect(s.targetReached, isTrue);
    expect(find.text('목표 달성! 다음 목표로 올릴까요?'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('IH로 올리기'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('IH로 올리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('올리기'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(studyProvider).toeicTarget, ToeicTarget.ih);
    expect(_c(tester).read(studyProvider).contentStep, 9);
    expect(find.text('목표 달성! 다음 목표로 올릴까요?'), findsNothing);
  });

  testWidgets('홈·기록: 모의고사 카드(일요일 권유), 목표 달성 제안, 기록 목록', (tester) async {
    await setPhone(tester);
    final base = _seeded();
    final store = MemoryStore(
      SavedData(
        profile: base.profile,
        contentStep: base.contentStep,
        onboarded: true,
        log: base.log,
        settings: base.settings,
        mocks: const [
          // 기기 점수로만 본 예전 모의고사: 등급 대신 '채점 필요'
          MockResult(date: '2026-11-15', level: 'IM2', target: 'IM3', scores: [62]),
          MockResult(date: '2026-11-21', level: 'IM3~IH', target: 'IM3', scores: [72], graded: true),
        ],
      ),
    );
    await tester.pumpWidget(_app(store: store));
    await tester.pumpAndSettle();
    expect(find.text('목표 달성! 다음 목표로 올릴까요?'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('토스 실전 모의고사'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('주말이에요 · 11문항 약 20분, 실전처럼'), findsOneWidget); // 11/22 일요일

    await tester.tap(find.text('괜찮아요'));
    await tester.pumpAndSettle();
    expect(find.text('목표 달성! 다음 목표로 올릴까요?'), findsNothing);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(_app(initial: '/progress', store: store));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('토스 모의고사'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('목표 IM3 · 140점 (140-150)'), findsOneWidget);
    expect(find.text('11월 21일'), findsOneWidget);
    expect(find.text('IM3~IH'), findsOneWidget);
    expect(find.text('채점 필요'), findsOneWidget);
    expect(find.text('평균 62점'), findsOneWidget);
    expect(find.text('모의고사 보기'), findsOneWidget);
  });

  testWidgets('설정에서 토스 목표를 바꾸면 난이도도 바뀐다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app(initial: '/settings'));
    await tester.pumpAndSettle();
    expect(find.text('IM3 · 140점'), findsOneWidget);
    await tester.tap(find.text('토스 목표'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('180점 · AL'));
    await tester.pumpAndSettle();
    final s = _c(tester).read(studyProvider);
    expect(s.toeicTarget, ToeicTarget.al);
    expect(s.contentStep, 11);
    expect(find.text('AL · 180점'), findsOneWidget);
  });

  testWidgets('결과(질문 묶음): 요약 띠 · 카드는 접혀 있고 하나만 펼침 · 목표 미달이면 고친 걸로 다시 말하기가 주 버튼', (tester) async {
    await setPhone(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        initial: '/toeic-today',
        grade: FakeGrade(targetMet: false),
        store: MemoryStore(
          _seeded(
            today: const TodayProgress(date: '2026-11-22', toeic: {'ra-1': _ra, 'pic-1': _ra}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Q5-7 질문에 답하기'), findsOneWidget);
    await tester.tap(find.text('시작'));
    for (var t = 0; t < 3; t++) {
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('준비 끝 · 바로 말하기'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('다 말했어요'));
      await tester.pump();
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // ① 요약 띠: 묶음 점수 · 목표 대비(아이콘과 글로) · 고칠 것 1개
    final strip = find.byKey(const ValueKey('toeic-summary'));
    expect(find.descendant(of: strip, matching: find.text('8/10')), findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('목표 IM3까지 조금 더')), findsOneWidget);
    expect(find.descendant(of: strip, matching: find.byIcon(Icons.trending_up_rounded)), findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('고칠 것 1개')), findsOneWidget);
    expect(find.bySemanticsLabel('고칠 말: a woman drink. 이렇게: a woman is drinking'), findsOneWidget);
    // CEFR 같은 다른 등급 표기는 없다
    expect(find.textContaining(RegExp(r'\b(A1|A2|B1|B2|C1|C2)\b')), findsNothing);

    // ② 카드 셋은 모두 접혀 있다
    expect(find.text('들린 대로'), findsNothing);
    expect(find.bySemanticsLabel('Q5 자세히 보기'), findsOneWidget);
    expect(find.bySemanticsLabel('Q6 자세히 보기'), findsOneWidget);
    await tester.tap(find.text('Q5').first);
    await tester.pumpAndSettle();
    expect(find.text('들린 대로'), findsOneWidget);
    expect(find.bySemanticsLabel('Q5 자세히 접기'), findsOneWidget);
    // 다른 카드를 펼치면 먼저 펼친 카드는 접힌다
    final q6 = find.descendant(of: find.byKey(const ValueKey('turn-6')), matching: find.text('Q6'));
    await tester.scrollUntilVisible(q6, 100, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(q6);
    await tester.pumpAndSettle();
    await tester.tap(q6);
    await tester.pumpAndSettle();
    Finder header(String label) =>
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label, skipOffstage: false);
    expect(find.text('들린 대로', skipOffstage: false), findsOneWidget);
    expect(header('Q6 자세히 접기'), findsOneWidget);
    await tester.scrollUntilVisible(header('Q5 자세히 보기'), -100, scrollable: find.byType(Scrollable).first);
    expect(header('Q5 자세히 보기'), findsOneWidget);
    expect(find.text('들린 대로', skipOffstage: false), findsOneWidget);

    // ④ 목표 미달: 고친 걸로 다시 말하기(주) / 다음(보조)
    expect(find.widgetWithText(FilledButton, '고친 걸로 다시 말하기'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '다음'), findsOneWidget);
    await tester.tap(find.text('고친 걸로 다시 말하기'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Q5 · 준비 시간'), findsOneWidget);
    expect(find.text('이번에 고칠 것'), findsOneWidget);
    expect(_c(tester).read(studyProvider).today.toeic.containsKey('q-1'), isFalse);
    semantics.dispose();
  });

  testWidgets('결과: 목표 수준이고 시간을 채웠으면 다음이 주 버튼, 다듬은 답을 문장마다 듣고 따라 말한다', (tester) async {
    await setPhone(tester);
    final speech = ManualSpeech();
    final speaker = FakeSpeaker();
    await tester.pumpWidget(
      _app(
        initial: '/toeic-today',
        speech: speech,
        speaker: speaker,
        grade: FakeGrade(improved: 'A woman is drinking coffee. She looks relaxed.'),
        store: MemoryStore(
          _seeded(
            today: const TodayProgress(date: '2026-11-22', toeic: {'ra-1': _ra}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('준비 끝 · 바로 말하기'));
    await tester.pump();
    await tester.pump();
    speech.say('This picture was taken in a cafe');
    await _seconds(tester, 25);
    speech.say('This picture was taken in a cafe and a woman is drinking coffee');
    await _seconds(tester, 5);
    await tester.pumpAndSettle();

    expect(find.text('목표 IM3 수준'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '다음'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '다시 하기'), findsOneWidget);
    expect(find.text('고친 걸로 다시 말하기'), findsNothing);

    // ③ 다듬은 답 따라 하기: 문장 단위
    final shadow = find.byKey(const ValueKey('toeic-shadowing'));
    await tester.scrollUntilVisible(shadow, 200, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: shadow, matching: find.text('다듬은 답 따라 하기')), findsOneWidget);
    expect(find.descendant(of: shadow, matching: find.text('A woman is drinking coffee.')), findsOneWidget);
    expect(find.descendant(of: shadow, matching: find.text('She looks relaxed.')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('문장 2 듣기'));
    await tester.pump();
    expect(speaker.spoken.last.$1, 'She looks relaxed.');
    speech.echo = true;
    await tester.tap(find.bySemanticsLabel('문장 2 따라 말하기'));
    await tester.pump();
    expect(find.text('듣고 있어요 · 다 말하면 한 번 더 눌러요'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('문장 2 따라 말하기 끝내기'));
    await tester.pumpAndSettle();
    expect(find.text('알아들은 단어 100%'), findsOneWidget);

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(studyProvider).today.toeic['pic-1']!.score, 80);
  });

  testWidgets('타이머 접근성: live region 은 단계 이름만, 10초·5초는 따로 알림, 전환·5초에 진동', (tester) async {
    await setPhone(tester);
    final announced = <String>[];
    final haptics = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
      final m = message as Map;
      if (m['type'] == 'announce') announced.add((m['data'] as Map)['message'] as String);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
      return null;
    });
    addTearDown(() {
      messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    String liveLabel() => tester
        .widget<Semantics>(find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true))
        .properties
        .label!;

    await tester.pumpWidget(_app(initial: '/toeic-today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump();
    expect(liveLabel(), 'Q1 준비 시간');
    await _seconds(tester, 34);
    // 매초 바뀌는 남은 초는 live region 에 넣지 않는다
    expect(liveLabel(), 'Q1 준비 시간');
    expect(announced, isEmpty);
    await _seconds(tester, 1);
    expect(announced, ['10초 남았어요']);
    expect(find.text('곧 끝나요'), findsNothing);
    await _seconds(tester, 5);
    expect(announced, ['10초 남았어요', '5초 남았어요']);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    // 남은 5초: 색 말고도 글과 아이콘으로
    expect(find.text('곧 끝나요'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

    await _seconds(tester, 5);
    await tester.pump();
    expect(liveLabel(), 'Q1 답하기');
    expect(haptics.last, 'HapticFeedbackType.mediumImpact');
    expect(find.text('곧 끝나요'), findsNothing);
    await _seconds(tester, 45);
    await tester.pumpAndSettle();
    expect(announced, ['10초 남았어요', '5초 남았어요', '10초 남았어요', '5초 남았어요']);
    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);
  });
}

/// 이미 끝낸 문장 읽기 결과 (다음 문항부터 시작하게)
const _ra = ToeicTaskRecord(type: ToeicTaskType.readAloud, score: 80);
