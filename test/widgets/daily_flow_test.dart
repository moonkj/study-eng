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
    for (var d = 10; d <= 21; d++) dateKey(DateTime(2026, 11, d)): DayRecord(accuracy: 0.95, levelScore: 700 + d * 2),
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

    // 홈으로 돌아가지 않고 다음 단계로 이어간다
    expect(find.text('표현 학습 완료!'), findsOneWidget);
    await tester.tap(find.text('이어서 하기'));
    await tester.pumpAndSettle();

    // ② 단어
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('알아요'));
      await tester.pumpAndSettle();
    }

    // ③ 말하기
    await tester.tap(find.text('이어서 하기'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.bySemanticsLabel('말하기 시작'));
      await tester.pumpAndSettle();
      expect(find.text('완벽해요'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('다음 문장'));
      await tester.pumpAndSettle();
    }

    // ④ 퀴즈: 모두 정답 선택. 이번엔 '나중에'로 홈에 갔다가 홈에서 시작
    await tester.tap(find.text('나중에 할게요'));
    await tester.pumpAndSettle();
    expect(find.text('남은 시간 약 3분 · 3/4'), findsOneWidget);
    await tester.tap(find.text('복습 퀴즈'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final quiz = container.read(studyProvider).pack.quiz;
    expect(quiz.where((q) => q.isRecall).length, 2); // 끝에 첫 글자 보고 쓰기 2문제
    for (var i = 0; i < quiz.length; i++) {
      if (quiz[i].isRecall) {
        expect(find.text(quiz[i].clue!), findsOneWidget);
        await tester.enterText(find.byType(TextField), ' ${quiz[i].choices[0].toUpperCase()} ');
        await tester.pump();
        await tester.tap(find.text('확인'));
      } else {
        await tester.tap(find.text(quiz[i].choices[quiz[i].answerIndex]));
      }
      await tester.pumpAndSettle();
      expect(find.text('정답이에요!'), findsOneWidget);
      await tester.tap(find.text(i < quiz.length - 1 ? '다음 문제' : '결과 보기'));
      await tester.pumpAndSettle();
    }

    expect(find.text('최고 기록 경신! 13일 연속'), findsOneWidget); // 어제까지 12일이 최고 기록
    expect(find.textContaining('13', findRichText: true), findsWidgets); // 연속 학습일 +1
    expect(find.text('12/12'), findsOneWidget);
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
    // 8시라 오늘 7:30은 지났다. 내일 아침까지 오늘을 빠지면 쉬는 날(12일 연속으로 1개)로 지킨 상태
    expect(reminder.scheduled.single.$2, '쉬는 날로 지켜 둔 12일');
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

  testWidgets('루틴을 끝내지 않았으면 완료 화면 대신 홈, 진단을 마친 사용자는 환영 화면 대신 홈', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(initial: '/complete'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 루틴'), findsOneWidget);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(app(initial: '/welcome'));
    await tester.pumpAndSettle();
    expect(find.text('레벨 진단 시작하기'), findsNothing);
    expect(find.text('오늘의 루틴'), findsOneWidget);
  });

  testWidgets('바로 연 학습 화면에서 닫으면 오류 없이 홈으로', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(initial: '/quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('오늘의 루틴'), findsOneWidget);
  });

  testWidgets('단어를 하던 중 새벽 4시가 지나도 진행이 지워지지 않고, 홈으로 돌아오면 오늘로 바뀐다', (tester) async {
    await setPhone(tester);
    var now = DateTime(2026, 11, 22, 3, 50);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reminderProvider.overrideWithValue(FakeReminder()),
          speakerProvider.overrideWithValue(FakeSpeaker()),
          storeProvider.overrideWithValue(MemoryStore(seeded())),
          clockProvider.overrideWithValue(() => now),
          speechInputProvider.overrideWithValue(_PerfectSpeech()),
        ],
        child: const TodayeApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('오늘의 단어 10개'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알아요'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(studyProvider).today.date, '2026-11-21'); // 새벽 3:50 은 전날 학습일

    now = DateTime(2026, 11, 22, 4, 5);
    await tester.tap(find.text('알아요'));
    await tester.pumpAndSettle();
    var st = container.read(studyProvider);
    expect(st.today.date, '2026-11-21');
    expect(st.wordRatings.length, 2); // 루틴 중에는 미룬다

    await tester.tap(find.byTooltip('홈으로'));
    await tester.pumpAndSettle();
    st = container.read(studyProvider);
    expect(st.today.date, '2026-11-22');
    expect(st.wordRatings, isEmpty);
  });
}

class _FailingSpeech implements SpeechInput {
  @override
  Future<SpeechAttempt> listen({required String expected, void Function(String partial)? onPartial}) async =>
      const SpeechAttempt.failed('마이크 권한이 필요해요.');

  @override
  Future<void> stop() async {}
}
