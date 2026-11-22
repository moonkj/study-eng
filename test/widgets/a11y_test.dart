import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/data/pack_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/srs.dart';

import 'daily_flow_test.dart' show app, seeded, setPhone;

void main() {
  SavedData withDueCard() {
    final s = seeded();
    return SavedData(
      profile: s.profile,
      contentStep: s.contentStep,
      onboarded: true,
      log: s.log,
      learned: {
        'w-reluctant': const LearnedItem(
          id: 'w-reluctant',
          kind: 'word',
          text: 'reluctant',
          meaning: '내키지 않는, 마지못해 하는',
          firstSeen: '2026-11-15',
        ),
      },
      cards: {'w-reluctant': ReviewCard(itemId: 'w-reluctant', stage: 1, due: DateTime(2026, 11, 21))},
    );
  }

  testWidgets('글씨 2배: 복습 카드가 넘치지 않고 평가 버튼이 세로로 쌓인다', (tester) async {
    await setPhone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(initial: '/review-session', store: MemoryStore(withDueCard())));
    await tester.pumpAndSettle();
    expect(find.text('reluctant'), findsOneWidget);
    await tester.tap(find.text('뜻 확인하기'));
    await tester.pumpAndSettle();
    final know = tester.getTopLeft(find.text('알았어요'));
    final dont = tester.getTopLeft(find.text('몰랐어요'));
    expect((know.dy - dont.dy).abs(), greaterThan(20)); // 세로 배치
    expect(tester.takeException(), isNull);
  });

  testWidgets('학습 화면 상단: 진행 상황을 스크린리더가 문장으로 읽는다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(initial: '/words'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('오늘의 단어, 10개 중 0개 완료'), findsOneWidget);
  });
}
