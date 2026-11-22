import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/core/theme/tokens.dart';
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

  testWidgets('글씨 2배: 단어 카드에서 뜻을 열어도 넘치지 않는다', (tester) async {
    await setPhone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(initial: '/words'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탭해서 뜻 보기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('학습 화면 상단: 진행 상황을 스크린리더가 문장으로 읽는다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(initial: '/words'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('오늘의 단어, 10개 중 0개 완료'), findsOneWidget);
  });

  testWidgets('설정에서 어둡게를 고르면 밤의 종이 팔레트로 바뀐다 (화면 위치 유지)', (tester) async {
    await setPhone(tester);
    addTearDown(() => AppColors.use(AppPalette.light));
    await tester.pumpWidget(app(initial: '/settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('화면 테마'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('어둡게 (밤의 종이)'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(find.text('어둡게 (밤의 종이)'), findsOneWidget); // 설정 화면 그대로
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final bg =
        scaffold.backgroundColor ?? Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor;
    expect(bg, AppPalette.dark.paper);
    expect(tester.takeException(), isNull);
  });
}
