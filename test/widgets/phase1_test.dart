import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/app/routine_flow.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/daily_adjuster.dart';
import 'package:todaye/features/speaking/speech_input.dart';

import '../domain/speech_input_test.dart' show FakeEngine;
import 'daily_flow_test.dart' show app, seeded, setPhone;

ProviderContainer _container([SavedData? data]) {
  final c = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(MemoryStore(data ?? seeded())),
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('정답률(난이도·레벨)은 고르는 문제로만, 쓰기 문제는 어휘 점수로, 스스로 채점한 것은 어디에도 넣지 않는다', () {
    final c = _container();
    final n = c.read(studyProvider.notifier);
    final quiz = c.read(studyProvider).pack.quiz;
    final recall = [
      for (var i = 0; i < quiz.length; i++)
        if (quiz[i].isRecall) i,
    ];
    expect(recall.length, 2);
    for (var i = 0; i < quiz.length; i++) {
      if (!quiz[i].isRecall) n.answerQuiz(i, quiz[i].answerIndex);
    }
    n.answerQuiz(recall[0], 1); // 직접 써서 틀림
    n.answerQuiz(recall[1], 0, selfGraded: true); // 떠올렸어요 → 맞았어요
    expect(c.read(studyProvider).today.selfGraded, {recall[1]});
    for (final step in RoutineStep.values) {
      n.complete(step);
    }
    final record = c.read(studyProvider).log['2026-11-22']!;
    expect(record.accuracy, 1.0); // 쓰기 문제 오답이 정답률을 깎지 않는다
    expect((record.quizCorrect, record.quizTotal), (11, 12)); // 완료 화면에는 모두 센다
  });

  test('어휘 점수: 직접 써 본 결과가 있으면 자가 평가와 반씩 섞는다', () {
    const r = DailyResult(
      quizCorrect: 10,
      quizTotal: 10,
      wordsKnown: 10,
      wordsTotal: 10,
      speakingAverage: null,
      expressionsAlreadyKnown: 0,
      expressionsTotal: 3,
      recallCorrect: 0,
      recallTotal: 2,
    );
    expect(r.vocabularyRatio, 0.5);
  });

  test('다시 말하면 더 높은 점수가 남는다', () {
    final c = _container();
    final n = c.read(studyProvider.notifier);
    final s = c.read(studyProvider).pack.sentences.first;
    n.recordSpeaking(s, s.en);
    n.recordSpeaking(s, 'hmm');
    expect(c.read(studyProvider).speaking[s.id]!.score, 100);
    n.recordSilent(s); // 속으로 따라 한 것도 점수를 지우지 않는다
    expect(c.read(studyProvider).speaking[s.id]!.score, 100);
  });

  test('조용 모드는 저장되어 앱을 다시 켜도 유지된다', () {
    final store = MemoryStore(seeded());
    ProviderContainer make() => ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8)),
      ],
    );
    final a = make();
    expect(a.read(quietModeProvider), isFalse);
    a.read(quietModeProvider.notifier).set(true);
    a.dispose();
    final b = make();
    addTearDown(b.dispose);
    expect(b.read(quietModeProvider), isTrue);
  });

  test('예상 시간은 실제 분량으로: 첫날이 4일차보다 짧다', () {
    final full = _container();
    // 저장 데이터가 없으면 1일차 (분량을 줄인 팩)
    final firstC = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(null)),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8)),
      ],
    );
    addTearDown(firstC.dispose);
    final long = remainingMinutes(full.read(studyProvider));
    final short = remainingMinutes(firstC.read(studyProvider));
    expect(short, lessThan(long));
    expect(long, inInclusiveRange(10, 16));
  });

  test('인식 힌트는 요청할 때만 엔진에 준다', () async {
    final engine = _HintEngine();
    final input = DeviceSpeechInput(engine: engine);
    final a = input.listen(expected: 'Hi.');
    await Future<void>.delayed(Duration.zero);
    expect(engine.hints.last, isFalse);
    engine.onResult!('hi', true);
    await a;
    final b = input.listen(expected: 'Hi.', hint: true);
    await Future<void>.delayed(Duration.zero);
    expect(engine.hints.last, isTrue);
    engine.onResult!('hi', true);
    await b;
  });

  testWidgets('쓰기 어려우면 떠올린 뒤 정답을 보고 스스로 채점한다', (tester) async {
    await setPhone(tester);
    final store = MemoryStore(seeded());
    await tester.pumpWidget(app(initial: '/', store: store));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final quiz = container.read(studyProvider).pack.quiz;
    final first = quiz.indexWhere((q) => q.isRecall);
    for (var i = 0; i < first; i++) {
      container.read(studyProvider.notifier).answerQuiz(i, quiz[i].answerIndex);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(initial: '/quiz', store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('쓰기 어려워요 · 떠올리고 정답 보기'));
    await tester.pumpAndSettle();
    expect(find.text('Actually'), findsOneWidget);
    await tester.tap(find.text('맞았어요'));
    await tester.pumpAndSettle();
    expect(find.text('정답이에요!'), findsOneWidget);
    final c2 = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(c2.read(studyProvider).today.selfGraded, {first});
  });
}

class _HintEngine extends FakeEngine {
  final hints = <bool>[];

  @override
  Future<void> listen({required String expected, required bool hint, required void Function(String, bool) onResult}) {
    hints.add(hint);
    return super.listen(expected: expected, hint: hint, onResult: onResult);
  }
}
