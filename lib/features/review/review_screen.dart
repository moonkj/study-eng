import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final now = s.now; // 학습일 기준 (새벽 4시 전에도 '내일' 계산이 맞게)
    final wrong = [
      for (final e in s.quizAnswers.entries)
        if (e.key < s.pack.quiz.length && s.pack.quiz[e.key].answerIndex != e.value) s.pack.quiz[e.key],
    ];
    final words = {for (final w in s.pack.words) w.id: w};
    final scheduled = s.cards.values.where((c) => words.containsKey(c.itemId)).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    // 홈·세션과 같은 기준 (한 번에 최대 20장)
    final dueCount = s.dueCount;

    return SafeArea(
      child: ListView(
        padding: readablePadding(context, maxWidth: 680),
        children: [
          Text('복습', style: AppType.title1(weight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: AppSpace.sm),
          Text('잊어버릴 때쯤 다시 보여드려요 (1 · 3 · 7 · 14 · 30일)', style: AppType.caption(color: context.colors.ink2)),
          const SizedBox(height: AppSpace.lg),
          PaperCard(
            elevated: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('오늘 복습할 카드', style: AppType.caption(color: context.colors.ink2)),
                      const SizedBox(height: AppSpace.xs),
                      Text('$dueCount장', style: AppType.enHero(weight: 500)),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                  onPressed: dueCount == 0 ? null : () => context.push('/review-session'),
                  child: const Text('복습 시작'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xxl),
          Text('오답 노트', style: AppType.body(weight: FontWeight.w700)),
          const SizedBox(height: AppSpace.sm),
          if (wrong.isEmpty)
            _Empty(text: '오늘 틀린 문제가 없어요. 퀴즈를 풀면 여기에 모여요.')
          else
            for (final q in wrong) ...[
              PaperCard(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.prompt, style: AppType.body(weight: FontWeight.w600)),
                    const SizedBox(height: AppSpace.sm),
                    englishSemantics(
                      q.choices[q.answerIndex],
                      Text(q.choices[q.answerIndex], style: AppType.enBody(color: context.colors.success)),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(q.explanation, style: AppType.callout(color: context.colors.ink2, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          const SizedBox(height: AppSpace.lg),
          Text('단어장', style: AppType.body(weight: FontWeight.w700)),
          const SizedBox(height: AppSpace.sm),
          if (scheduled.isEmpty)
            _Empty(text: '단어 카드를 평가하면 다음 복습 날짜가 여기에 표시돼요.')
          else
            PaperCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
              child: Column(
                children: [
                  for (final c in scheduled)
                    Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                      decoration: BoxDecoration(
                        border: c == scheduled.first ? null : Border(top: BorderSide(color: context.colors.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: englishSemantics(
                              words[c.itemId]!.word,
                              Text(words[c.itemId]!.word, style: AppType.enBody()),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              words[c.itemId]!.meaning,
                              style: AppType.caption(color: context.colors.ink2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Tag(
                            '${c.due.difference(DateTime(now.year, now.month, now.day)).inDays}일 뒤',
                            color: context.colors.ink,
                            background: context.colors.sand,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.row),
        border: Border.all(color: context.colors.line),
      ),
      child: Text(text, style: AppType.callout(color: context.colors.ink2, height: 1.5)),
    );
  }
}
