import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/toeic_level.dart';
import '../toeic/toeic_target.dart' show pickToeicTarget;

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
                padding: const EdgeInsets.fromLTRB(AppSpace.xxl, 64, AppSpace.xxl, 0),
                children: [
                  HighlightText(
                    'todaye',
                    highlight: 'today',
                    style: AppType.enDisplay(weight: 500, letterSpacing: -1, height: 1.2),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text('오늘의 영어', style: AppType.body(color: context.colors.ink2)),
                  const SizedBox(height: AppSpace.xxxl),
                  Text(
                    '하루 15분,\n토익스피킹 목표 점수까지',
                    style: AppType.title1(weight: FontWeight.w700, height: 1.35, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  // 가장 중요한 질문(목표 점수)을 가장 먼저
                  const _TargetRow(),
                  const SizedBox(height: AppSpace.xxl),
                  const _Point(n: '1', title: '레벨 진단 4분', body: '12문항으로 지금 토스 예상 등급을 알아봐요.'),
                  const _Point(
                    n: '2',
                    title: '매일 토스 루틴',
                    body: '답변에 쓸 표현·단어를 익히고, 실제 시험처럼 시간을 재고 말해요. 답은 Claude가 채점해요.',
                  ),
                  const _Point(n: '3', title: '목표에 맞춰 자동 조정', body: '목표 등급과 정답률을 보고 내일 문항·표현 난이도를 바꿔 드려요.'),
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
    useRootNavigator: true,
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xxl, AppSpace.xxl, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('영어로 짧은 대화를 할 수 있나요?', style: AppType.headline(weight: FontWeight.w700)),
            const SizedBox(height: AppSpace.sm),
            Text('나중에 설정에서 언제든 진단받을 수 있어요.', style: AppType.callout(color: context.colors.ink2)),
            const SizedBox(height: AppSpace.xl),
            FilledButton(onPressed: () => start(false), child: const Text('네, 간단한 대화는 돼요')),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton(onPressed: () => start(true), child: const Text('아직 어려워요 (쉬운 표현부터)')),
          ],
        ),
      ),
    ),
  );
}

/// 목표 점수 한 줄: 기본 IM3 · 140점, 탭하면 바꾸기
class _TargetRow extends ConsumerWidget {
  const _TargetRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(studyProvider).toeicTarget;
    return Material(
      color: context.colors.penBlueTint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => pickToeicTarget(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, color: context.colors.penBlue, size: 22),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text('목표 ${toeicLevelLabel(target.label)}', style: AppType.body(weight: FontWeight.w600)),
                ),
                Text(
                  '바꾸기',
                  style: AppType.callout(weight: FontWeight.w600, color: context.colors.penBlue),
                ),
                Icon(Icons.chevron_right_rounded, color: context.colors.penBlue, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.n, required this.title, required this.body});
  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.lineStrong, width: 1.5),
            ),
            child: Text(
              n,
              style: AppType.caption(weight: FontWeight.w600, color: context.colors.ink2),
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.body(weight: FontWeight.w700)),
                const SizedBox(height: AppSpace.xs),
                Text(body, style: AppType.callout(color: context.colors.ink2, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
