import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/core/layout/adaptive.dart';

import 'daily_flow_test.dart' show app;

Future<void> setSize(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  test('폭 구간', () {
    expect(WindowSize.of(375), WindowSize.compact);
    expect(WindowSize.of(507), WindowSize.compact); // Split View 절반 (iPad mini)
    expect(WindowSize.of(820), WindowSize.medium); // iPad Air 세로
    expect(WindowSize.of(1180), WindowSize.expanded); // iPad Air 가로
  });

  testWidgets('iPad 세로: 왼쪽 세로 내비게이션, 하단 탭 없음', (tester) async {
    await setSize(tester, const Size(820, 1180));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('t.'), findsOneWidget); // 좁은 세로 내비게이션 로고
    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('오늘의 루틴'), findsOneWidget);
  });

  testWidgets('iPad 가로: 내비게이션 글자가 펼쳐지고 홈이 2단이 된다', (tester) async {
    await setSize(tester, const Size(1180, 820));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('todaye'), findsOneWidget);
    expect(find.text('오늘 다시 볼 카드'), findsOneWidget); // 오른쪽 단: 복습 요약
    final routine = tester.getTopLeft(find.text('오늘의 루틴'));
    final review = tester.getTopLeft(find.text('오늘 다시 볼 카드'));
    expect(review.dx, greaterThan(routine.dx + 300));
  });

  testWidgets('iPad: 학습 화면은 읽기 좋은 폭(680)으로 가운데에 놓인다', (tester) async {
    await setSize(tester, const Size(1180, 820));
    await tester.pumpWidget(app(initial: '/words'));
    await tester.pumpAndSettle();
    final scaffold = tester.getSize(find.byType(Scaffold).last);
    expect(scaffold.width, lessThanOrEqualTo(680));
    final left = tester.getTopLeft(find.byType(Scaffold).last).dx;
    expect(left, closeTo((1180 - 680) / 2, 1));
  });

  testWidgets('키보드: 단어 화면 Space 로 뜻 보기, 3 으로 알아요', (tester) async {
    await setSize(tester, const Size(1180, 820));
    await tester.pumpWidget(app(initial: '/words'));
    await tester.pumpAndSettle();
    // AnimatedCrossFade 는 두 상태를 모두 그려 두므로 '눌러지는지'로 확인한다
    expect(find.text('탭해서 뜻 보기').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('탭해서 뜻 보기').hitTestable(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(find.text('1/10'), findsOneWidget);
  });

  testWidgets('키보드: 퀴즈 숫자키로 보기 선택, Enter 로 다음', (tester) async {
    await setSize(tester, const Size(1180, 820));
    await tester.pumpWidget(app(initial: '/quiz'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2); // 1번 문제 정답은 2번 보기
    await tester.pumpAndSettle();
    expect(find.text('정답이에요!'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('2/10'), findsOneWidget);
  });

  testWidgets('키보드: 키를 누르고 있어도 평가는 한 번만 들어간다', (tester) async {
    await setSize(tester, const Size(1180, 820));
    await tester.pumpWidget(app(initial: '/words'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(find.text('1/10'), findsOneWidget);
  });

  testWidgets('키보드: ⌘2 로 복습 탭, ⌘1 로 오늘 탭', (tester) async {
    await setSize(tester, const Size(1180, 820));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('오늘의 루틴'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('오늘의 루틴'), findsOneWidget);
  });
}
