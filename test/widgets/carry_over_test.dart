import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/store.dart';

import 'daily_flow_test.dart' show seeded;

ProviderContainer _on(MemoryStore store, DateTime at) {
  final c = ProviderContainer(
    overrides: [storeProvider.overrideWithValue(store), clockProvider.overrideWithValue(() => at)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('어제 표현까지만 했으면: 어제는 3분 루틴 날로 남고, 오늘은 어제 팩을 이어서 한다', () {
    final store = MemoryStore(seeded());
    final day1 = _on(store, DateTime(2026, 11, 22, 21));
    final n1 = day1.read(studyProvider.notifier);
    final e = day1.read(studyProvider).pack.expressions.first;
    n1.setExpressionKnown(e.id, false);
    n1.complete(RoutineStep.expressions);
    final topic1 = day1.read(studyProvider).pack.topic;
    final streak1 = day1.read(studyProvider).streakDays;

    final day2 = _on(store, DateTime(2026, 11, 23, 8));
    final s = day2.read(studyProvider);
    expect(s.today.carriedFrom, '2026-11-22');
    expect(s.today.date, '2026-11-23');
    expect(s.pack.topic, topic1);
    expect(s.done, {RoutineStep.expressions});
    expect(s.expressionKnown[e.id], isFalse);
    expect(s.log['2026-11-22']!.mini, isTrue);
    expect(s.streakDays, streak1 + 1); // 어제가 기록으로 남아 연속이 이어진다
    expect(s.isRepeatPack, isFalse); // 어제 처음 본 표현이라 복습 일정에 반영된다

    // 나머지를 끝내면 오늘 날짜로 정식 기록, 다음 날은 새 팩
    final n2 = day2.read(studyProvider.notifier);
    for (final step in RoutineStep.values.skip(1)) {
      n2.complete(step);
    }
    expect(day2.read(studyProvider).log['2026-11-23']!.mini, isFalse);
    final day3 = _on(store, DateTime(2026, 11, 24, 8));
    expect(day3.read(studyProvider).today.carriedFrom, isNull);
    expect(day3.read(studyProvider).done, isEmpty);
  });

  test('이어서 하기는 한 번만, 아무것도 안 했으면 이어 가지 않고, 새로 시작하면 오늘 팩으로', () {
    // 아무것도 안 한 날은 이어 가지 않는다
    final store0 = MemoryStore(seeded());
    _on(store0, DateTime(2026, 11, 22, 21)).read(studyProvider);
    expect(_on(store0, DateTime(2026, 11, 23, 8)).read(studyProvider).today.carriedFrom, isNull);

    final store = MemoryStore(seeded());
    final day1 = _on(store, DateTime(2026, 11, 22, 21));
    day1.read(studyProvider.notifier).setExpressionKnown(day1.read(studyProvider).pack.expressions.first.id, true);
    // 표현 단계를 끝내지 않았으면 3분 루틴 기록은 없지만 이어서 할 수 있다
    final day2 = _on(store, DateTime(2026, 11, 23, 8));
    final s2 = day2.read(studyProvider);
    expect(s2.today.carriedFrom, '2026-11-22');
    expect(s2.log.containsKey('2026-11-22'), isFalse);
    final cards = s2.cards;
    // 하루 더 지나도 다시 이어 가지 않는다
    day2.read(studyProvider.notifier).setExpressionKnown(s2.pack.expressions[1].id, true);
    expect(_on(store, DateTime(2026, 11, 24, 8)).read(studyProvider).today.carriedFrom, isNull);

    // 새로 시작: 오늘 팩, 이미 평가한 카드는 그대로
    final store2 = MemoryStore(seeded());
    final a = _on(store2, DateTime(2026, 11, 22, 21));
    a.read(studyProvider.notifier).setExpressionKnown(a.read(studyProvider).pack.expressions.first.id, true);
    final b = _on(store2, DateTime(2026, 11, 23, 8));
    final topicCarried = b.read(studyProvider).pack.topic;
    final cardsBefore = b.read(studyProvider).cards;
    b.read(studyProvider.notifier).dropCarried();
    final s3 = b.read(studyProvider);
    expect(s3.today.carriedFrom, isNull);
    expect(s3.done, isEmpty);
    expect(s3.pack.topic, isNot(topicCarried));
    expect(
      {for (final e in s3.cards.entries) e.key: (e.value.stage, e.value.due)},
      {for (final e in cardsBefore.entries) e.key: (e.value.stage, e.value.due)},
    );
    expect(cards, isNotEmpty);
  });
}
