import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// 첫 실행 화면: 레벨 진단으로 안내한다.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 64, 28, 0),
                children: [
                  HighlightText(
                    'todaye',
                    highlight: 'today',
                    style: serif(44, weight: 500, letterSpacing: -1, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text('오늘의 영어', style: sans(15, color: AppColors.ink2)),
                  const SizedBox(height: 40),
                  Text(
                    '하루 15분,\n내 레벨에 딱 맞는 영어 루틴',
                    style: sans(26, weight: FontWeight.w700, height: 1.35, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 28),
                  const _Point(n: '1', title: '레벨 진단 4분', body: '12문항이면 지금 실력과 약한 영역을 알 수 있어요.'),
                  const _Point(n: '2', title: '매일 맞춤 학습', body: '표현 3개, 단어 10개, 따라 말하기, 복습 퀴즈까지.'),
                  const _Point(n: '3', title: '알아서 난이도 조정', body: '정답률을 보고 내일 학습을 조금씩 바꿔 드려요.'),
                ],
              ),
            ),
            BottomActions(
              children: [
                FilledButton(onPressed: () => context.push('/level-test'), child: const Text('레벨 진단 시작하기')),
                TextButton(onPressed: () => _askLevel(context, ref), child: const Text('진단 없이 바로 시작')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 진단을 건너뛸 때 한 가지만 물어 시작 레벨을 고른다 (초보자가 첫날 너무 어려워 포기하지 않게)
void _askLevel(BuildContext context, WidgetRef ref) {
  void start(bool beginner) {
    Navigator.pop(context);
    ref.read(studyProvider.notifier).skipLevelTest(beginner: beginner);
    context.go('/');
  }

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('영어로 짧은 대화를 할 수 있나요?', style: sans(18, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('나중에 설정에서 언제든 진단받을 수 있어요.', style: sans(13, color: AppColors.ink2)),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => start(false), child: const Text('네, 간단한 대화는 돼요 (B1부터)')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => start(true), child: const Text('아직 어려워요 (A2부터)')),
          ],
        ),
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.n, required this.title, required this.body});
  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.lineStrong, width: 1.5),
            ),
            child: Text(
              n,
              style: sans(13, weight: FontWeight.w600, color: AppColors.ink2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sans(16, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: sans(14, color: AppColors.ink2, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
