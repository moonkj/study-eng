import 'dart:async';

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

class FakeGrade implements GradeSource {
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
    return const GradeResult(
      score: 8,
      maxScore: 10,
      level: 'IH',
      summaryKo: '전달이 분명해요',
      fixes: [GradeFix(from: 'a woman drink', to: 'a woman is drinking', whyKo: '진행형')],
      targetMet: true,
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

    expect(find.text('"Welcome to City Library. We are open from nine to six."'), findsOneWidget);
    expect(find.textContaining('1초 / 45초 동안 말함 · 단어 11개 · 원문과 100% 일치'), findsOneWidget);
    expect(find.text('· 쉼표에서 잠깐 쉬어요.'), findsOneWidget);
    expect(find.text('다시 하기'), findsOneWidget);
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

    expect(find.text('핵심 표현 1/2개 사용'), findsOneWidget);
    expect(find.text('사진 단어 · sip 홀짝이다'), findsOneWidget);
    expect(find.text('모범 답안'), findsOneWidget);
    expect(find.text('This picture was taken in a cafe. A woman is drinking coffee.'), findsOneWidget);
    expect(find.textContaining('/ 30초 동안 말함'), findsOneWidget);
    final play = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Q3 모범 답안 듣기');
    await tester.ensureVisible(play);
    await tester.tap(play);
    expect(speaker.spoken.last.$1, 'This picture was taken in a cafe. A woman is drinking coffee.');
    expect(find.text('채점하는 중'), findsNothing);

    // 다시 하기: 처음부터 다시
    await tester.tap(find.text('다시 하기'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Q3 · 준비 시간'), findsOneWidget);
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
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('전달이 분명해요'), findsOneWidget);
    expect(find.text('목표 수준'), findsOneWidget);
    expect(find.textContaining('a woman is drinking', findRichText: true), findsOneWidget);
    // IH 목표: IH 모범 답안
    expect(find.text('This photo shows an open-plan office.'), findsOneWidget);
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
        await tester.scrollUntilVisible(find.text('Q7'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Q7'), findsOneWidget);
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
    final grade = FakeGrade();
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
    expect(find.text('IH'), findsWidgets); // 서버 점수 80 → IH
    expect(find.text('목표 IM3 달성!'), findsOneWidget);
    // 표 질문은 듣기로만: 소리로 읽어 줬다
    expect(speaker.spoken.map((e) => e.$1), contains('Where is the workshop?'));
    expect(speaker.spoken.where((e) => e.$1 == 'What sessions are in the morning?').length, 2);
    expect(grade.calls.length, 11);

    final s = _c(tester).read(studyProvider);
    final m = s.mocks.single;
    expect(m.scores.length, 11);
    expect(m.scores.every((e) => e == 80), isTrue);
    expect(m.level, 'IH');
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
          MockResult(date: '2026-11-15', level: 'IM2', target: 'IM3', scores: [62]),
          MockResult(date: '2026-11-21', level: 'IM3', target: 'IM3', scores: [72]),
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
}

/// 이미 끝낸 문장 읽기 결과 (다음 문항부터 시작하게)
const _ra = ToeicTaskRecord(type: ToeicTaskType.readAloud, score: 80);
