import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/layout/adaptive.dart';
import '../core/theme/tokens.dart';
import '../features/complete/complete_screen.dart';
import '../features/expression/expression_screen.dart';
import '../features/home/home_screen.dart';
import '../features/level_result/level_result_screen.dart';
import '../features/level_test/level_test_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/review/review_screen.dart';
import '../features/review/review_session_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/speaking/speaking_screen.dart';
import '../features/welcome/welcome_screen.dart';
import '../features/words/words_screen.dart';

/// 첫 실행(레벨 진단 전)에도 들어갈 수 있는 경로
const _onboardingPaths = {'/welcome', '/level-test', '/level-result'};

GoRouter buildRouter({String initialLocation = '/', bool Function()? isOnboarded}) => GoRouter(
  initialLocation: initialLocation,
  redirect: (context, state) {
    final onboarded = isOnboarded?.call() ?? true;
    if (!onboarded && !_onboardingPaths.contains(state.matchedLocation)) return '/welcome';
    return null;
  },
  routes: [
    _focused('/welcome', const WelcomeScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => TabShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/review', builder: (_, _) => const ReviewScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())],
        ),
      ],
    ),
    _focused('/expressions', const ExpressionScreen()),
    _focused('/words', const WordsScreen()),
    _focused('/speaking', const SpeakingScreen()),
    _focused('/quiz', const QuizScreen()),
    _focused('/complete', const CompleteScreen()),
    _focused('/review-session', const ReviewSessionScreen()),
    _focused('/level-test', const LevelTestScreen()),
    _focused('/level-result', const LevelResultScreen()),
  ],
);

class TabShell extends StatelessWidget {
  const TabShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const tabs = [
    (Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, '오늘'),
    (Icons.replay_rounded, Icons.replay_rounded, '복습'),
    (Icons.bar_chart_rounded, Icons.bar_chart_rounded, '기록'),
    (Icons.settings_outlined, Icons.settings_rounded, '설정'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    // iPad 키보드: ⌘1~4 로 탭 이동
    final tabKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];
    Widget withTabKeys(Widget child) => CallbackShortcuts(
      bindings: {
        for (var i = 0; i < tabs.length; i++)
          SingleActivator(tabKeys[i], meta: true, includeRepeats: false): () => _go(i),
      },
      // 탭 화면에는 포커스 받을 위젯이 없어 단축키가 닿지 않으므로 여기서 포커스를 받는다
      child: Focus(autofocus: true, child: child),
    );
    if (size.isWide) {
      // iPad: 왼쪽 세로 내비게이션 + 내용
      return withTabKeys(
        Scaffold(
          body: Row(
            children: [
              _SideNav(current: shell.currentIndex, onSelect: _go, extended: size == WindowSize.expanded),
              VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
              // 내용 영역의 실제 폭을 MediaQuery 로 알려 준다 (여백·단 나눔이 내비게이션 폭을 빼고 계산되게)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => MediaQuery(
                    // 왼쪽 안전 영역은 내비게이션이 이미 처리했다
                    data: MediaQuery.of(context).copyWith(
                      size: Size(c.maxWidth, c.maxHeight),
                      padding: MediaQuery.paddingOf(context).copyWith(left: 0),
                      viewPadding: MediaQuery.viewPaddingOf(context).copyWith(left: 0),
                    ),
                    child: shell,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return withTabKeys(
      Scaffold(
        body: shell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.paper,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: shell.currentIndex == i,
                          button: true,
                          child: InkWell(
                            onTap: () => _go(i),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  shell.currentIndex == i ? tabs[i].$2 : tabs[i].$1,
                                  size: 22,
                                  color: shell.currentIndex == i ? AppColors.ink : AppColors.ink2,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  tabs[i].$3,
                                  style: sans(
                                    12,
                                    weight: shell.currentIndex == i ? FontWeight.w700 : FontWeight.w500,
                                    color: shell.currentIndex == i ? AppColors.ink : AppColors.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iPad 용 세로 내비게이션. 가로(넓은) 화면에서는 글자를 옆에 펼친다.
class _SideNav extends StatelessWidget {
  const _SideNav({required this.current, required this.onSelect, required this.extended});
  final int current;
  final ValueChanged<int> onSelect;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: extended ? 220 : 88,
      color: AppColors.paper,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 8, vertical: 20),
          child: Column(
            crossAxisAlignment: extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(left: extended ? 12 : 0, bottom: 28),
                child: Text(
                  extended ? 'todaye' : 't.',
                  style: serif(extended ? 28 : 26, weight: 500, letterSpacing: -0.5),
                ),
              ),
              for (var i = 0; i < TabShell.tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Semantics(
                    selected: current == i,
                    button: true,
                    label: TabShell.tabs[i].$3,
                    excludeSemantics: true,
                    child: Material(
                      color: current == i ? AppColors.sand : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: DecoratedBox(
                        // 선택 표시를 배경색만이 아니라 왼쪽 막대로도 (배경과 대비가 낮아서)
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: current == i ? Border(left: BorderSide(color: AppColors.ink, width: 3)) : null,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onSelect(i),
                          // 큰 글씨에서도 넘치지 않게 최소 높이
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: extended ? 48 : 60,
                              minWidth: extended ? double.infinity : 72,
                              maxWidth: extended ? double.infinity : 72,
                            ),
                            child: extended
                                ? Row(
                                    children: [
                                      const SizedBox(width: 12),
                                      Icon(
                                        current == i ? TabShell.tabs[i].$2 : TabShell.tabs[i].$1,
                                        size: 22,
                                        color: current == i ? AppColors.ink : AppColors.ink2,
                                      ),
                                      const SizedBox(width: 14),
                                      Text(
                                        TabShell.tabs[i].$3,
                                        style: sans(
                                          15,
                                          weight: current == i ? FontWeight.w700 : FontWeight.w500,
                                          color: current == i ? AppColors.ink : AppColors.ink2,
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        current == i ? TabShell.tabs[i].$2 : TabShell.tabs[i].$1,
                                        size: 22,
                                        color: current == i ? AppColors.ink : AppColors.ink2,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        TabShell.tabs[i].$3,
                                        style: sans(
                                          12,
                                          weight: current == i ? FontWeight.w700 : FontWeight.w500,
                                          color: current == i ? AppColors.ink : AppColors.ink2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 학습 화면처럼 한 가지에 집중하는 화면: iPad 에서는 읽기 좋은 폭으로 가운데 둔다.
class _Focused extends StatelessWidget {
  const _Focused({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
      child: ReadableWidth(maxWidth: 680, child: child),
    );
  }
}

/// 학습 화면 전환: 살짝 위로 떠오르며 나타난다 (240ms)
GoRoute _focused(String path, Widget screen) => GoRoute(
  path: path,
  pageBuilder: (context, state) => CustomTransitionPage<void>(
    key: state.pageKey,
    // '동작 줄이기'면 즉시 전환
    transitionDuration: motion(context, AppMotion.base),
    reverseTransitionDuration: motion(context, AppMotion.fast),
    child: _Focused(child: screen),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  ),
);
