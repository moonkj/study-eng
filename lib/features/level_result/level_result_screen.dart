import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/level.dart';

class LevelResultScreen extends ConsumerWidget {
  const LevelResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(studyProvider).profile;
    final level = p.overall;
    final weak = p.weakestSkill;
    final strong = p.strongestSkill;
    final weakIsLow = p.skills[weak]!.step < level.step;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                child: IconButton(
                  tooltip: '닫기',
                  onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                children: [
                  Text(
                    '내 레벨',
                    style: sans(13, weight: FontWeight.w600, color: AppColors.penBlue, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '지금 레벨에 딱 맞는\n학습을 준비했어요',
                    style: sans(24, weight: FontWeight.w700, height: 1.35, letterSpacing: -0.4),
                  ),
                  const SizedBox(height: 24),
                  PaperCard(
                    elevated: true,
                    radius: AppRadius.hero,
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: level.cefr.label,
                                          style: serif(
                                            64,
                                            weight: 500,
                                            color: AppColors.penBlue,
                                            height: 0.95,
                                            letterSpacing: -1,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '.${level.sub}',
                                          style: serif(32, color: AppColors.ink2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(level.cefr.koDescription, style: sans(15, weight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Text('CEFR 기준', style: sans(12, color: AppColors.ink2)),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _Scale(level: level),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('영역별 실력', style: sans(15, weight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  for (final skill in Skill.values) ...[
                    _SkillBar(skill: skill, level: p.skills[skill]!, weak: skill == weak && weakIsLow),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(color: AppColors.sand, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.edit_outlined, size: 20, color: AppColors.penBlue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: sans(14, height: 1.6),
                              children: [
                                TextSpan(text: '${strong.ko}은(는) 강점이에요. '),
                                if (weakIsLow) ...[
                                  TextSpan(
                                    text: '${weak.ko} 연습',
                                    style: sans(14, weight: FontWeight.w700, height: 1.6),
                                  ),
                                  TextSpan(
                                    text: '이 조금 부족해요. 앞으로 2주 동안 ${weak.ko} 비중을 높이고, ${level.cefr.label} 표현 위주로 출제할게요.',
                                  ),
                                ] else
                                  TextSpan(text: '영역별 실력이 고르게 좋아요. ${level.cefr.label} 표현 위주로 출제할게요.'),
                              ],
                            ),
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
                FilledButton(onPressed: () => context.go('/'), child: const Text('오늘 학습 시작하기')),
                TextButton(onPressed: () => context.pushReplacement('/level-test'), child: const Text('레벨 다시 진단하기')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Scale extends StatelessWidget {
  const _Scale({required this.level});
  final Level level;

  @override
  Widget build(BuildContext context) {
    final c = level.cefr.index;
    final within = (level.step % 3 + level.progressToNext) / 3;
    return Semantics(
      label: 'A1부터 C1 중 ${level.label}',
      child: Row(
        children: [
          for (final cefr in Cefr.values)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: cefr == Cefr.c1 ? 0 : 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThinProgress(
                      cefr.index < c ? 1 : (cefr.index == c ? within : 0),
                      height: 6,
                      color: cefr.index < c ? AppColors.penBlueSoft : AppColors.penBlue,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cefr.label,
                      style: sans(
                        11,
                        weight: cefr.index == c ? FontWeight.w700 : FontWeight.w400,
                        color: cefr.index == c ? AppColors.penBlue : AppColors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SkillBar extends StatelessWidget {
  const _SkillBar({required this.skill, required this.level, required this.weak});
  final Skill skill;
  final Level level;
  final bool weak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 76, child: Text(skill.ko, style: sans(14))),
        Expanded(
          child: ThinProgress(
            (level.score + 1) / (Level.maxScore + 1),
            height: 8,
            color: weak ? AppColors.ember : AppColors.penBlue,
            track: AppColors.line,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            level.label,
            textAlign: TextAlign.right,
            style: sans(13, weight: FontWeight.w600, color: weak ? AppColors.error : AppColors.ink),
          ),
        ),
      ],
    );
  }
}
