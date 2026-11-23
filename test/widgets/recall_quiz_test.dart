import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/study_log.dart';

import 'daily_flow_test.dart' show app, seeded, setPhone, labeled, FakeSpeaker;

void main() {
  testWidgets('첫 글자 쓰기: 틀리면 내 답과 정답을, 떠오르지 않으면 정답을 보여 주고 오답으로 센다', (tester) async {
    await setPhone(tester);
    final speaker = FakeSpeaker();
    final store = MemoryStore(seeded());
    await tester.pumpWidget(app(initial: '/', store: store));
    await tester.pumpAndSettle();
    var container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final quiz = container.read(studyProvider).pack.quiz;
    final first = quiz.indexWhere((q) => q.isRecall);
    for (var i = 0; i < first; i++) {
      container.read(studyProvider.notifier).answerQuiz(i, quiz[i].answerIndex);
    }
    // 저장된 진행으로 퀴즈를 다시 열면 첫 쓰기 문제부터
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(initial: '/quiz', store: store, speaker: speaker));
    await tester.pumpAndSettle();
    expect(find.text('첫 글자를 보고 빈칸에 들어갈 영어를 써 주세요'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'actualy');
    await tester.pump();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('아쉬워요. 정답과 이 부분이 달라요'), findsOneWidget);
    expect(find.text('actualy'), findsWidgets);
    await tester.tap(labeled('정답 듣기'));
    expect(speaker.spoken.last.$1, "Actually, I'm a little tired."); // 빈칸을 채운 문장 전체
    await tester.tap(find.text('다음 문제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('떠오르지 않아요 · 정답 보기'));
    await tester.pumpAndSettle();
    expect(find.text('아쉬워요. 정답과 이 부분이 달라요'), findsOneWidget);
    container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final s = container.read(studyProvider);
    expect(s.quizCorrect, first); // 쓰기 2문제는 오답
    expect(tester.takeException(), isNull);
  });

  testWidgets('완료 화면 점수는 루틴을 끝낼 때 저장한 기록을 보여 준다', (tester) async {
    await setPhone(tester);
    final data = seeded();
    final store = MemoryStore(
      SavedData(
        profile: data.profile,
        contentStep: data.contentStep,
        onboarded: true,
        log: {
          ...data.log,
          '2026-11-22': const DayRecord(accuracy: 0.75, levelScore: 760, quizCorrect: 9, quizTotal: 12),
        },
        today: const TodayProgress(date: '2026-11-22', done: {'expressions', 'words', 'speaking', 'quiz'}),
      ),
    );
    await tester.pumpWidget(app(initial: '/complete', store: store));
    await tester.pumpAndSettle();
    expect(find.text('9/12'), findsOneWidget);
    expect(find.text('틀린 문제 다시 보기'), findsOneWidget);
  });
}
