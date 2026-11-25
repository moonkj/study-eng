import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/toeic.dart';

/// "IM3 · 140점 (140-150)"
String targetLabel(ToeicTarget t) => '${t.label} · ${t.score}점 (${t.range})';

/// 목표 고르기 목록 (설정·첫 토스 말하기)
class ToeicTargetList extends StatelessWidget {
  const ToeicTargetList({super.key, required this.selected, required this.onSelect});
  final ToeicTarget selected;
  final ValueChanged<ToeicTarget> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final t in ToeicTarget.values)
          ListTile(
            minTileHeight: 52,
            title: Text('${t.score}점 · ${t.label}', style: AppType.body(weight: FontWeight.w500)),
            subtitle: Text('공식 구간 ${t.range}', style: AppType.caption(color: context.colors.ink2)),
            trailing: t == selected ? Icon(Icons.check_rounded, color: context.colors.penBlue) : null,
            selected: t == selected,
            onTap: () => onSelect(t),
          ),
      ],
    );
  }
}

/// 목표 바꾸기 시트
Future<void> pickToeicTarget(BuildContext context, WidgetRef ref) async {
  final current = ref.read(studyProvider).toeicTarget;
  final picked = await showModalBottomSheet<ToeicTarget>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xxl, 0, AppSpace.xxl, AppSpace.xs),
              child: Text('토스 목표 점수', style: AppType.headline(weight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xxl, 0, AppSpace.xxl, AppSpace.sm),
              child: Text('목표에 맞춰 문항·모범 답안과 표현·단어 난이도가 바뀌어요.', style: AppType.caption(color: ctx.colors.ink2)),
            ),
            ToeicTargetList(selected: current, onSelect: (t) => Navigator.pop(ctx, t)),
          ],
        ),
      ),
    ),
  );
  if (picked != null) ref.read(studyProvider.notifier).setToeicTarget(picked);
}

/// 모의고사 예상 등급이 목표에 닿았을 때: 다음 목표로 올릴지 묻는다
class TargetReachedCard extends ConsumerWidget {
  const TargetReachedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final next = s.toeicTarget.next;
    if (!s.targetReached || next == null) return const SizedBox.shrink();
    return AppBanner(
      kind: BannerKind.success,
      icon: Icons.emoji_events_outlined,
      title: '목표 달성! 다음 목표로 올릴까요?',
      message: '모의고사 예상 ${s.mocks.last.level} · 지금 목표 ${s.toeicTarget.label} → 다음 ${next.label} (${next.range})',
      actions: [
        TextButton(onPressed: ref.read(studyProvider.notifier).dismissTargetSuggestion, child: const Text('괜찮아요')),
        Expanded(
          child: FilledButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('목표를 ${next.label}로 올릴까요?'),
                  content: Text('${targetLabel(next)}\n문항·모범 답안과 표현·단어 난이도가 한 단계 올라가요.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('올리기')),
                  ],
                ),
              );
              if (ok == true) ref.read(studyProvider.notifier).setToeicTarget(next);
            },
            child: Text('${next.label}로 올리기'),
          ),
        ),
      ],
    );
  }
}

/// 토스 모의고사로 가는 카드 (주말에는 더 눈에 띄게)
class MockEntryCard extends StatelessWidget {
  const MockEntryCard({super.key, required this.weekend, required this.onTap, this.last});
  final bool weekend;
  final VoidCallback onTap;

  /// 지난 모의고사 예상 등급
  final String? last;

  @override
  Widget build(BuildContext context) {
    return ActionRow(
      icon: Icons.timer_outlined,
      title: '토스 실전 모의고사',
      subtitle: weekend ? '주말이에요 · 11문항 약 20분, 실전처럼' : '11문항 약 20분${last == null ? '' : ' · 지난번 $last'}',
      tinted: weekend,
      onTap: onTap,
    );
  }
}

/// 모의고사 기록 한 줄
class MockHistoryRow extends StatelessWidget {
  const MockHistoryRow({super.key, required this.date, required this.level, required this.average, required this.met});
  final String date;
  final String level;
  final int average;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(date, style: AppType.caption(color: context.colors.ink2)),
          ),
          ScoreBadge(level: level, met: met),
          const Spacer(),
          Text('평균 $average점', style: AppType.callout()),
        ],
      ),
    );
  }
}
