import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/level.dart';
import '../../domain/srs.dart';

class CompleteScreen extends ConsumerWidget {
  const CompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final adj = s.adjustment;
    final now = s.profile.overall;
    final before = adj == null ? now : Level(now.score - adj.levelDelta);
    final speaking = s.speakingAverage;
    final newWords = s.wordRatings.values.where((r) => r != SelfRating.know).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                children: [
                  Center(
                    child: Container(
                      width: 112,
                      height: 112,
                      decoration: const BoxDecoration(
                        color: AppColors.ink,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.sand, spreadRadius: 10)],
                      ),
                      child: const Icon(Icons.local_fire_department_outlined, size: 46, color: AppColors.highlighter),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${s.streakDays}', style: serif(44, weight: 500, letterSpacing: -1)),
                          TextSpan(
                            text: '일 연속',
                            style: sans(22, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text('오늘 루틴 완료!', style: sans(22, weight: FontWeight.w700, letterSpacing: -0.4)),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      '표현 ${s.pack.expressions.length}개, 단어 ${s.pack.words.length}개, 문장 ${s.speaking.length}개를 말했어요',
                      textAlign: TextAlign.center,
                      style: sans(14, color: AppColors.ink2),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      _Stat(value: '${s.quizCorrect}/${s.pack.quiz.length}', label: '퀴즈'),
                      const SizedBox(width: 8),
                      _Stat(value: speaking == null ? '-' : '${speaking.round()}', label: '말하기 평균'),
                      const SizedBox(width: 8),
                      _Stat(value: '$newWords', label: '새 단어'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PaperCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('레벨 점수', style: sans(14, weight: FontWeight.w600)),
                            const Spacer(),
                            if (adj != null)
                              Text(
                                '${adj.levelDelta >= 0 ? '+' : ''}${adj.levelDelta}',
                                style: sans(
                                  13,
                                  weight: FontWeight.w700,
                                  color: adj.levelDelta >= 0 ? AppColors.success : AppColors.error,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(now.label, style: serif(18, weight: 600, color: AppColors.penBlue)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  height: 8,
                                  child: Stack(
                                    children: [
                                      const Positioned.fill(child: ColoredBox(color: AppColors.line)),
                                      FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        heightFactor: 1,
                                        widthFactor: now.progressToNext,
                                        child: const ColoredBox(color: AppColors.highlighter),
                                      ),
                                      FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        heightFactor: 1,
                                        widthFactor: before.step == now.step ? before.progressToNext : 0,
                                        child: const ColoredBox(color: AppColors.penBlue),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(now.next.label, style: serif(18, color: AppColors.ink2)),
                          ],
                        ),
                        if (before.step < now.step) ...[
                          const SizedBox(height: 10),
                          Text(
                            '레벨 업! ${before.label} → ${now.label}',
                            style: sans(13, weight: FontWeight.w700, color: AppColors.success),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.penBlueTint,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '내일은 이렇게 준비할게요',
                          style: sans(12, weight: FontWeight.w600, color: AppColors.penBlue, letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 10),
                        for (final r in s.lastAdjustmentReasons)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.north_east_rounded, size: 16, color: AppColors.penBlue),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(r, style: sans(14, height: 1.55))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            BottomActions(
              children: [
                FilledButton(onPressed: () => context.go('/'), child: const Text('홈으로')),
                TextButton(onPressed: () => context.push('/quiz'), child: const Text('틀린 문제 다시 보기')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PaperCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        radius: 16,
        child: Column(
          children: [
            Text(value, style: serif(26, weight: 500)),
            const SizedBox(height: 2),
            Text(label, style: sans(12, color: AppColors.ink2)),
          ],
        ),
      ),
    );
  }
}
