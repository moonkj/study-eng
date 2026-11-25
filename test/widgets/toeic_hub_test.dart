import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/app.dart';
import 'package:todaye/app/routine_flow.dart' show toeicDailyProvider;
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/audio/tts.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/grade_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/data/toeic.dart';
import 'package:todaye/domain/toeic_feedback.dart';
import 'package:todaye/features/speaking/speech_input.dart';
import 'package:todaye/features/toeic/toeic_hub_screen.dart';
import 'package:todaye/features/toeic/toeic_task.dart';

import '../domain/reminder_test.dart' show FakeReminder;
import '../support/fixed_fallback.dart';
import '../support/toeic_fixture.dart';
import 'daily_flow_test.dart' show FakeSpeaker, seeded, setPhone;
import 'ipad_test.dart' show setSize;
import 'toeic_test.dart' show ScriptedSpeech;

SavedData _seeded({int? target = 140, List<MockResult> mocks = const []}) {
  final s = seeded();
  return SavedData(
    profile: s.profile,
    contentStep: s.contentStep,
    onboarded: true,
    log: s.log,
    settings: AppSettings(toeicTarget: target),
    mocks: mocks,
  );
}

Widget _app({AppStore? store, bool noBank = false}) => ProviderScope(
  overrides: [
    reminderProvider.overrideWithValue(FakeReminder()),
    speakerProvider.overrideWithValue(FakeSpeaker()),
    storeProvider.overrideWithValue(store ?? MemoryStore(_seeded())),
    clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8, 0)),
    speechInputProvider.overrideWithValue(ScriptedSpeech((_) => 'This picture was taken in a cafe')),
    fallbackPackProvider.overrideWithValue(fixedSamplePackFor),
    toeicBankProvider.overrideWithValue(noBank ? null : toeicFixture),
    gradeSourceProvider.overrideWithValue(null),
  ],
  child: const TodayeApp(initialLocation: '/toeic'),
);

ProviderContainer _c(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Finder _labeledStart(String prefix) => find.byWidgetPredicate(
  (w) => w is Semantics && (w.properties.label?.startsWith(prefix) ?? false) && w.properties.button == true,
);

void main() {
  testWidgets('토스 허브: 목표 · 유형 5개 · 모의고사 · 내 답 모음(빈 상태) · 더 연습하기가 보인다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('나의 토스 목표'), findsOneWidget);
    expect(find.text('IM3'), findsOneWidget);
    expect(find.text('140점 · 공식 구간 140-150'), findsOneWidget);
    // 채점 기록이 없으면 홈 목표 카드와 같은 진단 어림 '예상' 등급
    expect(find.textContaining(RegExp(r'^예상 (NL|NM|NH|IL|IM1|IM2|IM3|IH|AL) · \d+점$')), findsOneWidget);
    expect(find.textContaining('레벨 진단으로 본 대략의 등급이에요'), findsOneWidget);
    // CEFR 은 보이지 않는다
    expect(find.textContaining('B1'), findsNothing);

    for (final name in ['문장 읽기', '사진 묘사', '질문 답하기', '표 보고 답하기', '의견 말하기']) {
      expect(_labeledStart('$name 한 문항 연습'), findsOneWidget);
    }
    expect(find.text('Q5-7'), findsOneWidget);
    expect(find.textContaining('아직 기록 없음'), findsNWidgets(5));

    await tester.scrollUntilVisible(find.text('대화 듣기'), 200);
    expect(find.text('실전 모의고사 · 11문항'), findsOneWidget);
    expect(find.text('첫 모의고사로 지금 위치를 확인해요 · 약 20분'), findsOneWidget);
    expect(find.textContaining('한 문항 연습을 하면 내가 말한 답과 모범 답안이 여기 모여요'), findsOneWidget);
    // 빈 상태: 다음 행동 + 걸리는 시간
    expect(find.textContaining(RegExp(r'^사진 묘사 한 문항 · 약 \d+분$')), findsOneWidget);
    expect(find.text('내 상황으로 말하기'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('내 상황으로 말하기'));
    await tester.pumpAndSettle();
    expect(find.text('내 상황으로 말하기'), findsWidgets);
  });

  testWidgets('목표 머리를 누르면 목표 바꾸기 시트, 채점된 모의고사 등급 범위를 보여 준다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(
      _app(
        store: MemoryStore(
          _seeded(
            mocks: const [
              MockResult(date: '2026-11-20', level: 'IM3~IH', target: 'IM3', scores: [70], graded: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('IM3~IH'), findsOneWidget);
    expect(find.text('11월 20일 모의고사 채점 기준'), findsOneWidget);
    expect(find.text('목표 달성'), findsOneWidget);

    await tester.tap(find.text('나의 토스 목표'));
    await tester.pumpAndSettle();
    expect(find.text('토스 목표 점수'), findsOneWidget);
    await tester.tap(find.text('160점 · IH'));
    await tester.pumpAndSettle();
    expect(_c(tester).read(studyProvider).settings.toeicTarget, 160);
    expect(find.text('IH'), findsOneWidget);
  });

  testWidgets('한 문항 연습: 그 유형 문항 하나만 하고 허브로, 내 답 모음에 담기고 오늘 루틴 기록은 그대로', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(_labeledStart('사진 묘사 한 문항 연습'));
    await tester.pumpAndSettle();
    expect(find.text('한 문항 연습 · 사진 묘사'), findsOneWidget);
    expect(find.text('Q3 사진 묘사'), findsOneWidget);

    await tester.tap(find.text('시작'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('준비 끝 · 바로 말하기'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('다 말했어요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // 허브로 돌아왔다
    expect(find.text('나의 토스 목표'), findsOneWidget);
    expect(find.text('방금 말한 답을 내 답 모음에 담았어요'), findsOneWidget);
    final c = _c(tester);
    final answers = c.read(practiceLogProvider);
    expect(answers.single.task.type, ToeicTaskType.picture);
    // 오늘 루틴의 사진과는 다른 사진
    expect(answers.single.task.id, isNot(c.read(toeicDailyProvider)!.picture.id));
    expect(answers.single.outcomes.single.transcript, 'This picture was taken in a cafe');
    // 연습은 오늘 루틴·유형별 점수에 넣지 않는다
    final s = c.read(studyProvider);
    expect(s.today.toeic, isEmpty);
    expect(s.toeicLog, isEmpty);

    // 알림(스낵바)이 사라진 뒤에 누른다 (화면 아래 줄을 가리지 않게)
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(answers.single.task.title), 200);
    expect(find.text('1개'), findsOneWidget);
    await tester.tap(find.text(answers.single.task.title));
    await tester.pumpAndSettle();
    expect(find.text('This picture was taken in a cafe'), findsWidgets);
    expect(find.text('모범 답안'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('연습 중 닫기를 누르면 허브로 돌아온다 (기록 없음)', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(_labeledStart('의견 말하기 한 문항 연습'));
    await tester.pumpAndSettle();
    expect(find.text('Q11 의견 말하기'), findsOneWidget);
    await tester.tap(find.byTooltip('연습 그만하고 토스 허브로'));
    await tester.pumpAndSettle();
    expect(find.text('나의 토스 목표'), findsOneWidget);
    expect(_c(tester).read(practiceLogProvider), isEmpty);
  });

  testWidgets('문항 모음이 없으면 연습 대신 안내, 모의고사는 누를 수 없다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(_app(noBank: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('문항을 불러오지 못했어요'), findsOneWidget);
    expect(_labeledStart('사진 묘사 한 문항 연습'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPad 폭에서도 넘치지 않는다', (tester) async {
    await setSize(tester, const Size(1180, 820));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('나의 토스 목표'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('대화 듣기'), 200);
    expect(tester.takeException(), isNull);
  });

  test('한 문항 연습 문항: 오늘 루틴·이미 연습한 문항을 피하고, 모두 피할 문항이면 그래도 하나는 고른다', () {
    final date = DateTime(2026, 11, 22);
    final first = practiceTask(toeicFixture, ToeicTaskType.picture, ToeicTarget.im3, date);
    final second = practiceTask(toeicFixture, ToeicTaskType.picture, ToeicTarget.im3, date, avoid: {first.id});
    expect(second.id, isNot(first.id));
    expect({first.id, second.id}, {'pic-1', 'pic-2'}); // 목표 단계(basic) 문항만
    final again = practiceTask(toeicFixture, ToeicTaskType.picture, ToeicTarget.im3, date, avoid: {'pic-1', 'pic-2'});
    expect(again.type, ToeicTaskType.picture);
    // IH 목표면 IH 문항
    expect(practiceTask(toeicFixture, ToeicTaskType.readAloud, ToeicTarget.ih, date).id, 'ra-ih');
  });
}
