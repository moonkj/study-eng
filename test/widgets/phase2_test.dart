import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/core/notifications/reminder.dart';
import 'package:todaye/data/pack_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/mastery.dart';
import 'package:todaye/domain/srs.dart';
import 'package:todaye/domain/study_log.dart';

import 'daily_flow_test.dart' show app, seeded, setPhone;

/// 예전에 배운 표현 하나(한 번 복습 통과, 오늘 복습할 차례)를 넣은 저장 데이터
SavedData withLearnedExpression() {
  final d = seeded();
  const id = 'exp-old-make-it';
  return SavedData(
    profile: d.profile,
    contentStep: d.contentStep,
    onboarded: true,
    log: d.log,
    learned: {
      id: const LearnedItem(
        id: id,
        kind: 'expression',
        text: 'Can you make it ~?',
        meaning: '~에 올 수 있어?',
        firstSeen: '2026-11-08',
      ),
    },
    cards: {id: ReviewCard(itemId: id, stage: 1, due: DateTime(2026, 11, 22))},
  );
}

ProviderContainer _container(SavedData data) {
  final c = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(MemoryStore(data)),
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 22, 8)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('알림 본문에 그날 만날 표현: 오늘은 오늘 팩, 그 뒤로는 배운 표현을 돌아가며', () {
    final c = _container(withLearnedExpression());
    final s = c.read(studyProvider);
    expect(reminderTeaser(s, 0)!.text, s.pack.expressions.first.pattern);
    expect(reminderTeaser(s, 3), isNotNull);
    final plan = planReminders(
      now: DateTime(2026, 11, 22, 6),
      studyToday: DateTime(2026, 11, 22),
      minutes: 7 * 60,
      doneToday: false,
      streak: 3,
      restsLeft: 0,
      longest: 3,
      days: 2,
      teaser: (k) => reminderTeaser(s, k),
    );
    expect(plan.first.body, contains(s.pack.expressions.first.pattern));
  });

  test('3분 루틴: 표현만 끝내도 연속 기록이 이어지고, 레벨·정답률 판단에는 쓰지 않는다', () {
    final c = _container(seeded());
    final n = c.read(studyProvider.notifier);
    n.finishMini(); // 표현을 끝내기 전에는 기록하지 않는다
    expect(c.read(studyProvider).log.containsKey('2026-11-22'), isFalse);
    n.complete(RoutineStep.expressions);
    final before = c.read(studyProvider).profile.overall.score;
    n.finishMini();
    final s = c.read(studyProvider);
    expect(s.log['2026-11-22']!.mini, isTrue);
    expect(s.streakDays, 13);
    expect(s.profile.overall.score, before);
    // 저장했다 다시 읽어도 3분 루틴 날로 남는다
    final back = DayRecord.fromJson(s.log['2026-11-22']!.toJson());
    expect(back.mini, isTrue);
    // 다음 날 난이도 비교에는 3분 루틴 날을 건너뛴다
    expect(previousRecord(s.log, DateTime(2026, 11, 23))!.accuracy, 0.95);
  });

  test('숙련 단계: 새로움 → 익히는 중 → 졸업 → 완전히 익힘, 오늘 졸업한 항목', () {
    final d = DateTime(2026, 11, 22);
    expect(masteryOf(null), Mastery.fresh);
    expect(masteryOf(ReviewCard(itemId: 'a', stage: 2, due: d)), Mastery.learning);
    expect(masteryOf(ReviewCard(itemId: 'a', stage: 5, due: d)), Mastery.graduated);
    expect(masteryOf(ReviewCard(itemId: 'a', stage: 7, due: d)), Mastery.mastered);
    expect(
      graduatedToday(
        {'a': ReviewCard(itemId: 'a', stage: 4, due: d)},
        {'a': ReviewCard(itemId: 'a', stage: 5, due: d)},
      ),
      ['a'],
    );
    final l = const LearnedItem(id: 'x', kind: 'expression', text: 'run late', meaning: '늦다', firstSeen: '2026-11-08');
    expect(oldestRemembered(['x'], {'x': l}, d)!.days, 14);
  });

  testWidgets('복습: 한 번 통과한 표현은 한국어 뜻을 보고 영어로 떠올린다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(initial: '/review-session', store: MemoryStore(withLearnedExpression())));
    await tester.pumpAndSettle();
    expect(find.text('~에 올 수 있어?'), findsOneWidget);
    expect(find.text('Can you make it ~?'), findsNothing);
    await tester.tap(find.text('말해 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('100점'), findsOneWidget); // 테스트 음성 입력은 목표 문장을 그대로 돌려준다
    expect(find.text('Can you make it ~?'), findsOneWidget); // 말하면 정답이 바로 보인다
    await tester.tap(find.text('알았어요'));
    await tester.pumpAndSettle();
    expect(find.text('1장 복습 완료'), findsOneWidget);
  });

  testWidgets('내 표현: 숙련 단계별로 모아 보여 준다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(initial: '/my-expressions', store: MemoryStore(withLearnedExpression())));
    await tester.pumpAndSettle();
    expect(find.text('익히는 중 1'), findsOneWidget);
    expect(find.text('Can you make it ~?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
