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
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(tooltip: '닫기', onPressed: () => popOrHome(context), icon: const Icon(Icons.close_rounded)),
                  const SizedBox(width: 4),
                  Text('내 표현', style: sans(18, weight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    '${items.length}개',
                    style: sans(13, weight: FontWeight.w600, color: context.colors.ink2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('오늘의 표현을 배우면 여기에 모여요', style: sans(14, color: context.colors.ink2)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        _Summary(groups: groups),
                        for (final e in groups.entries)
                          if (e.value.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Text(
                              '${e.key.ko} ${e.value.length}',
                              style: sans(14, weight: FontWeight.w700, color: context.colors.ink2),
                            ),
                            const SizedBox(height: 8),
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
                  Text('${groups[m]?.length ?? 0}', style: serif(24, weight: 600)),
                  const SizedBox(height: 2),
                  Text(m.ko, style: sans(12, color: context.colors.ink2)),
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
        padding: const EdgeInsets.only(bottom: 8),
        child: PaperCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.text, style: serif(17, weight: 500)),
                    const SizedBox(height: 2),
                    Text(item.meaning, style: sans(13, color: context.colors.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
