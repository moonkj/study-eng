import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/app.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/audio/tts.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/study_log.dart';
import 'package:todaye/features/speaking/speech_input.dart';

import '../domain/reminder_test.dart' show FakeReminder;

class _PerfectSpeech implements SpeechInput {
  @override
  Future<SpeechAttempt> listen({required String expected, void Function(String partial)? onPartial}) async {
    onPartial?.call(expected);
    return SpeechAttempt.heard(expected);
  }

  @override
  Future<void> stop() async {}
}

class FakeSpeaker implements Speaker {
  final spoken = <(String, bool)>[];

  @override
  void configure({required String voice, required double speed}) {}

  @override
  Future<void> speak(String text, {bool slow = false}) async => spoken.add((text, slow));

  @override
  Future<void> stop() async {}
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

Widget app({String initial = '/', AppStore? store, Speaker? speaker, Reminder? reminder}) => ProviderScope(
  overrides: [
    reminderProvider.overrideWithValue(reminder ?? FakeReminder()),
    speakerProvider.overrideWithValue(speaker ?? FakeSpeaker()),
    storeProvider.overrideWithValue(store ?? MemoryStore(seeded())),
    clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8, 0)),
    speechInputProvider.overrideWithValue(_PerfectSpeech()),
  ],
  child: TodayeApp(initialLocation: initial),
);

/// Semantics(label: ...) 로 감싼 버튼 찾기
Finder labeled(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

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
    expect(find.text('오늘 하면 13일'), findsOneWidget); // 어제까지 12일 연속, 오늘 아직
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
    expect(find.text('내일 몇 시에 알려 드릴까요?'), findsOneWidget); // 첫 완료 때 알림 제안

    final s = container.read(studyProvider);
    expect(s.allDone, isTrue);
    expect(s.contentStep, 8);
    expect(s.lastAdjustmentReasons.first, contains('정답률 100%'));
  });

  testWidgets('듣기 버튼은 설정한 음성으로 읽어주고, 0.8배는 느리게 읽는다', (tester) async {
    await setPhone(tester);
    final speaker = FakeSpeaker();
    await tester.pumpWidget(app(speaker: speaker));
    await tester.pumpAndSettle();

    await tester.tap(labeled('예문 듣기').first);
    expect(speaker.spoken.last, ("I've been meaning to call you.", false));

    await tester.tap(find.text('예문 따라 말하기'));
    await tester.pumpAndSettle();
    await tester.tap(labeled('천천히 듣기'));
    expect(speaker.spoken.last, ("Actually, I think I'll take the bus today.", true));
  });

  testWidgets('음성 인식이 실패하면 이유를 보여주고, 스스로 체크하고 넘어갈 수 있다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(MemoryStore(seeded())),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8, 0)),
          speakerProvider.overrideWithValue(FakeSpeaker()),
          speechInputProvider.overrideWithValue(_FailingSpeech()),
          reminderProvider.overrideWithValue(FakeReminder()),
        ],
        child: const TodayeApp(initialLocation: '/speaking'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('말하기 시작'));
    await tester.pumpAndSettle();
    expect(find.text('마이크 권한이 필요해요.'), findsOneWidget);
    await tester.tap(find.text('소리 내어 읽었어요 (넘어가기)'));
    await tester.pumpAndSettle();
    // 채점하지 않았으므로 점수 없이 다음 문장으로 넘어가고, 평균에도 넣지 않는다
    expect(find.text('완벽해요'), findsNothing);
    final s = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)).read(studyProvider);
    expect(s.spokenCount, 1);
    expect(s.speaking, isEmpty);
  });

  testWidgets('설정에서 아침 알림을 켜면 7:30에 예약된다', (tester) async {
    await setPhone(tester);
    final reminder = FakeReminder();
    await tester.pumpWidget(app(initial: '/settings', reminder: reminder));
    await tester.pumpAndSettle();
    expect(find.text('꺼짐'), findsOneWidget);
    await tester.tap(find.text('아침 알림'));
    await tester.pumpAndSettle();
    expect(find.text('매일 오전 7:30'), findsOneWidget);
    expect(reminder.scheduled.single.$1, 450);
    expect(reminder.scheduled.single.$2, '12일 연속 학습 중');
  });

  testWidgets('첫 실행이면 환영 화면이 나오고, 건너뛰면 B1.1로 시작한다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(store: MemoryStore()));
    await tester.pumpAndSettle();

    expect(find.text('레벨 진단 시작하기'), findsOneWidget);
    await tester.tap(find.text('진단 없이 바로 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('네, 간단한 대화는 돼요 (B1부터)'));
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

class _FailingSpeech implements SpeechInput {
  @override
  Future<SpeechAttempt> listen({required String expected, void Function(String partial)? onPartial}) async =>
      const SpeechAttempt.failed('마이크 권한이 필요해요.');

  @override
  Future<void> stop() async {}
}
