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
                padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, 0, 0),
                child: IconButton(
                  tooltip: '닫기',
                  // 바로 아래가 환영 화면일 수 있으므로(첫 진단) 항상 홈으로
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xs, AppSpace.xxl, 0),
                children: [
                  Text(
                    '내 레벨',
                    style: AppType.callout(weight: FontWeight.w600, color: context.colors.penBlue, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    ref.watch(studyProvider).packLoading ? '지금 레벨에 맞는\n학습을 준비하고 있어요' : '지금 레벨에 딱 맞는\n학습을 준비했어요',
                    style: AppType.title1(weight: FontWeight.w700, height: 1.35, letterSpacing: -0.4),
                  ),
                  const SizedBox(height: AppSpace.xxl),
                  PaperCard(
                    elevated: true,
                    radius: AppRadius.hero,
                    padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xxl, AppSpace.xxl, AppSpace.xxl),
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
                                          // 레벨 결과의 큰 등급 글자만 AppType 밖 예외 (진단 결과 한 번 보는 화면)
                                          style: serif(
                                            64,
                                            weight: 500,
                                            color: context.colors.penBlue,
                                            height: 0.95,
                                            letterSpacing: -1,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '.${level.sub}',
                                          style: AppType.enHero(weight: 400, color: context.colors.ink2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpace.xs),
                                  Text(level.cefr.koDescription, style: AppType.body(weight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Text('CEFR 기준', style: AppType.caption(color: context.colors.ink2)),
                          ],
                        ),
                        const SizedBox(height: AppSpace.lg),
                        _Scale(level: level),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xxl),
                  Text('영역별 실력', style: AppType.body(weight: FontWeight.w700)),
                  const SizedBox(height: AppSpace.md),
                  for (final skill in Skill.values) ...[
                    _SkillBar(skill: skill, level: p.skills[skill]!, weak: skill == weak && weakIsLow),
                    const SizedBox(height: AppSpace.md),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.lg),
                    decoration: BoxDecoration(
                      color: context.colors.sand,
                      borderRadius: BorderRadius.circular(AppRadius.row),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.edit_outlined, size: 20, color: context.colors.penBlue),
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: AppType.callout(height: 1.6),
                              children: [
                                // 모든 영역이 같은 점수면(진단을 건너뛴 경우) 강점을 단정하지 않는다
                                if (strong != weak && p.skills[strong] != p.skills[weak])
                                  TextSpan(text: '${strong.ko}은(는) 강점이에요. '),
                                if (weakIsLow) ...[
                                  TextSpan(
                                    text: '${weak.ko} 연습',
                                    style: AppType.callout(weight: FontWeight.w700, height: 1.6),
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
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: Text(ref.watch(studyProvider).allDone ? '홈으로' : '오늘 학습 시작하기'),
                ),
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
                padding: EdgeInsets.only(right: cefr == Cefr.c1 ? 0 : AppSpace.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThinProgress(
                      cefr.index < c ? 1 : (cefr.index == c ? within : 0),
                      height: 6,
                      color: cefr.index < c ? context.colors.penBlueSoft : context.colors.penBlue,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      cefr.label,
                      style: AppType.micro(
                        weight: cefr.index == c ? FontWeight.w700 : FontWeight.w400,
                        color: cefr.index == c ? context.colors.penBlue : context.colors.ink2,
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
        SizedBox(width: 76, child: Text(skill.ko, style: AppType.callout())),
        Expanded(
          child: ThinProgress(
            (level.score + 1) / (Level.maxScore + 1),
            height: 8,
            color: weak ? context.colors.ember : context.colors.penBlue,
            track: context.colors.line,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            level.label,
            textAlign: TextAlign.right,
            style: AppType.callout(weight: FontWeight.w600, color: weak ? context.colors.error : context.colors.ink),
          ),
        ),
      ],
    );
  }
}
