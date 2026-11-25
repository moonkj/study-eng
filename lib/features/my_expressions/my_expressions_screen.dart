import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/pack_source.dart';
import '../../domain/mastery.dart';
import '../../domain/srs.dart';

/// 지금까지 배운 표현 모음: 숙련 단계별로 모아 보여 준다 (수집하는 즐거움, 포인트·순위는 쓰지 않는다)
class MyExpressionsScreen extends ConsumerWidget {
  const MyExpressionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final items = [
      for (final l in s.learned.values)
        if (l.kind == 'expression') l,
    ]..sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
    final groups = {
      for (final m in Mastery.values.reversed)
        m: [
          for (final l in items)
            if (masteryOf(s.cards[l.id]) == m) l,
        ],
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.xl, 0),
              child: Row(
                children: [
                  IconButton(tooltip: '닫기', onPressed: () => popOrHome(context), icon: const Icon(Icons.close_rounded)),
                  const SizedBox(width: AppSpace.xs),
                  Text('내 표현', style: AppType.headline(weight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    '${items.length}개',
                    style: AppType.caption(weight: FontWeight.w600, color: context.colors.ink2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('오늘의 표현을 배우면 여기에 모여요', style: AppType.callout(color: context.colors.ink2)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xxl),
                      children: [
                        _Summary(groups: groups),
                        for (final e in groups.entries)
                          if (e.value.isNotEmpty) ...[
                            const SizedBox(height: AppSpace.xl),
                            Text(
                              '${e.key.ko} ${e.value.length}',
                              style: AppType.callout(weight: FontWeight.w700, color: context.colors.ink2),
                            ),
                            const SizedBox(height: AppSpace.sm),
                            for (final l in e.value) _Row(item: l, card: s.cards[l.id]),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.groups});
  final Map<Mastery, List<LearnedItem>> groups;

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      child: Row(
        children: [
          for (final m in Mastery.values) ...[
            Expanded(
              child: Column(
                children: [
                  Text('${groups[m]?.length ?? 0}', style: AppType.enTitle(weight: 600)),
                  const SizedBox(height: AppSpace.xs),
                  Text(m.ko, style: AppType.caption(color: context.colors.ink2)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.card});
  final LearnedItem item;
  final ReviewCard? card;

  @override
  Widget build(BuildContext context) {
    final m = masteryOf(card);
    final progress = masteryProgress(card);
    return Semantics(
      label: '${item.text}, ${item.meaning}, ${m.ko}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: PaperCard(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.text, style: AppType.enBody(weight: 500)),
                    const SizedBox(height: AppSpace.xs),
                    Text(item.meaning, style: AppType.caption(color: context.colors.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              // 숙련 점: 1·3·7·14·30일 간격을 통과할 때마다 하나씩 채워진다
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < Srs.intervals.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m == Mastery.graduated || m == Mastery.mastered || i < progress
                            ? context.colors.success
                            : context.colors.track,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
