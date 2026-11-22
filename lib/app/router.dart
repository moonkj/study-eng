import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import '../features/complete/complete_screen.dart';
import '../features/expression/expression_screen.dart';
import '../features/home/home_screen.dart';
import '../features/level_result/level_result_screen.dart';
import '../features/level_test/level_test_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/review/review_screen.dart';
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
    GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
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
    GoRoute(path: '/expressions', builder: (_, _) => const ExpressionScreen()),
    GoRoute(path: '/words', builder: (_, _) => const WordsScreen()),
    GoRoute(path: '/speaking', builder: (_, _) => const SpeakingScreen()),
    GoRoute(path: '/quiz', builder: (_, _) => const QuizScreen()),
    GoRoute(path: '/complete', builder: (_, _) => const CompleteScreen()),
    GoRoute(path: '/level-test', builder: (_, _) => const LevelTestScreen()),
    GoRoute(path: '/level-result', builder: (_, _) => const LevelResultScreen()),
  ],
);

class TabShell extends StatelessWidget {
  const TabShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, '오늘'),
    (Icons.replay_rounded, Icons.replay_rounded, '복습'),
    (Icons.bar_chart_rounded, Icons.bar_chart_rounded, '기록'),
    (Icons.settings_outlined, Icons.settings_rounded, '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.paper,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: shell.currentIndex == i,
                      button: true,
                      child: InkWell(
                        onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              shell.currentIndex == i ? _tabs[i].$2 : _tabs[i].$1,
                              size: 22,
                              color: shell.currentIndex == i ? AppColors.ink : AppColors.ink2,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _tabs[i].$3,
                              style: sans(
                                11,
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
    );
  }
}
