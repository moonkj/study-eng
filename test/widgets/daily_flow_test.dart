import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/app.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/study_log.dart';
import 'package:todaye/features/speaking/speech_input.dart';

class _PerfectSpeech implements SpeechInput {
  @override
  bool get isDemo => false;

  @override
  Future<String> listen(String target) async => target;
}

/// 진단을 마치고 11/10~11/21 12일 연속 학습한 사용자
SavedData seeded() => SavedData(
  profile: const LearnerProfile(
    overall: Level(764),
    skills: {
      Skill.vocabulary: Level(980),
      Skill.grammar: Level(720),
      Skill.listening: Level(700),
      Skill.speaking: Level(430),
    },
  ),
  contentStep: 7,
  onboarded: true,
  log: {
    for (var d = 10; d <= 21; d++) dateKey(DateTime(2026, 11, d)): DayRecord(accuracy: 0.88, levelScore: 700 + d * 2),
  },
);

Widget app({String initial = '/', AppStore? store}) => ProviderScope(
  overrides: [
    storeProvider.overrideWithValue(store ?? MemoryStore(seeded())),
    clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8, 0)),
    speechInputProvider.overrideWithValue(_PerfectSpeech()),
  ],
  child: TodayeApp(initialLocation: initial),
);

Future<void> setPhone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('홈: 날짜, 오늘의 표현, 루틴, 레벨이 보인다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('11월 22일 일요일'), findsOneWidget);
    expect(find.text('좋은 아침이에요'), findsOneWidget);
    expect(find.text('계속 ~하려고 했어'), findsOneWidget);
    expect(find.text('오늘의 표현 3개'), findsOneWidget);
    expect(find.text('B1.2'), findsOneWidget);
    expect(find.text('12일째'), findsOneWidget);
  });

  testWidgets('하루 루틴 전체를 끝내면 완료 화면과 내일 조정이 나온다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // ① 표현
    await tester.tap(find.text('오늘의 표현 3개'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('처음 봐요'));
      await tester.pump();
      await tester.tap(find.text(i < 2 ? '다음 표현' : '표현 학습 완료'));
      await tester.pumpAndSettle();
    }

    // ② 단어
    await tester.tap(find.text('오늘의 단어 10개'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('알아요'));
      await tester.pumpAndSettle();
    }

    // ③ 말하기
    await tester.tap(find.text('예문 따라 말하기'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.bySemanticsLabel('말하기 시작'));
      await tester.pumpAndSettle();
      expect(find.text('완벽해요'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('다음 문장'));
      await tester.pumpAndSettle();
    }

    // ④ 퀴즈: 모두 첫 번째 보기 선택
    await tester.tap(find.text('복습 퀴즈'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final quiz = container.read(studyProvider).pack.quiz;
    for (var i = 0; i < quiz.length; i++) {
      await tester.tap(find.text(quiz[i].choices[quiz[i].answerIndex]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(i < quiz.length - 1 ? '다음 문제' : '결과 보기'));
      await tester.pumpAndSettle();
    }

    expect(find.text('오늘 루틴 완료!'), findsOneWidget);
    expect(find.textContaining('13', findRichText: true), findsWidgets); // 연속 학습일 +1
    expect(find.text('10/10'), findsOneWidget);
    expect(find.textContaining('정답률 100%'), findsOneWidget);

    final s = container.read(studyProvider);
    expect(s.allDone, isTrue);
    expect(s.contentStep, 8);
  });

  testWidgets('첫 실행이면 환영 화면이 나오고, 건너뛰면 B1.1로 시작한다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(store: MemoryStore()));
    await tester.pumpAndSettle();

    expect(find.text('레벨 진단 시작하기'), findsOneWidget);
    await tester.tap(find.text('건너뛰고 B1부터 시작'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 루틴'), findsOneWidget);
    expect(find.text('B1.1'), findsOneWidget);
    expect(find.text('오늘부터 시작'), findsOneWidget);
  });

  testWidgets('레벨 진단 12문항을 마치면 결과 화면으로 간다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(initial: '/level-test'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 12; i++) {
      await tester.tap(find.text('잘 모르겠어요 (찍지 않기)'));
      await tester.pumpAndSettle();
    }
    expect(find.text('내 레벨'), findsOneWidget);
    expect(find.text('오늘 학습 시작하기'), findsOneWidget);
  });
}
