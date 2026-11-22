import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String koreanDate(DateTime d) => '${d.month}월 ${d.day}일 ${_weekdays[d.weekday - 1]}요일';

String greeting(DateTime d) => switch (d.hour) {
  < 5 => '늦은 밤이에요',
  < 12 => '좋은 아침이에요',
  < 18 => '좋은 오후예요',
  _ => '오늘 하루 수고했어요',
};

const routinePaths = {
  RoutineStep.expressions: '/expressions',
  RoutineStep.words: '/words',
  RoutineStep.speaking: '/speaking',
  RoutineStep.quiz: '/quiz',
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final now = ref.watch(clockProvider)();
    final exp = s.pack.expressions.first;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.xxl),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(koreanDate(now), style: sans(13, color: AppColors.ink2, letterSpacing: 0.2)),
                    const SizedBox(height: 4),
                    Text(greeting(now), style: sans(26, weight: FontWeight.w700, letterSpacing: -0.5)),
                  ],
                ),
              ),
              _StreakChip(days: s.streakDays),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          if (s.packLoading) ...[
            const _PreparingCard(),
            const SizedBox(height: 22),
            _LevelStrip(state: s),
          ] else ...[
            if (s.packError != null && s.untouched) ...[
              _FallbackNotice(message: s.packError!, onRetry: () => ref.read(studyProvider.notifier).loadTodayPack()),
              const SizedBox(height: 12),
            ],

            // 오늘의 표현 카드
            PaperCard(
              elevated: true,
              radius: AppRadius.hero,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "TODAY'S EXPRESSION",
                        style: sans(12, weight: FontWeight.w600, color: AppColors.penBlue, letterSpacing: 1),
                      ),
                      const Spacer(),
                      Text('1 / ${s.pack.expressions.length}', style: sans(12, color: AppColors.ink2)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HighlightText(
                    exp.pattern,
                    highlight: exp.highlight,
                    style: serif(30, weight: 500, height: 1.15, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 6),
                  Text(exp.meaning, style: sans(15, color: AppColors.ink2)),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '"${exp.examples.first.en}"',
                          style: serif(15, italic: true, color: AppColors.inkSoft),
                        ),
                      ),
                      RoundIconButton(
                        icon: Icons.volume_up_rounded,
                        label: '예문 듣기',
                        onPressed: () => ref.read(sayProvider)(exp.examples.first.en),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('오늘의 루틴', style: sans(17, weight: FontWeight.w700)),
                const Spacer(),
                Text('약 12분 · ${s.done.length}/4 완료', style: sans(13, color: AppColors.ink2)),
              ],
            ),
            const SizedBox(height: 10),
            for (final step in RoutineStep.values) ...[_RoutineRow(step: step, state: s), const SizedBox(height: 8)],

            const SizedBox(height: 6),
            _LevelStrip(state: s),
          ],
        ],
      ),
    );
  }
}

/// Claude 가 오늘의 맞춤 팩을 만드는 동안
class _PreparingCard extends StatelessWidget {
  const _PreparingCard();

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      elevated: true,
      radius: AppRadius.hero,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S PACK",
            style: sans(12, weight: FontWeight.w600, color: AppColors.penBlue, letterSpacing: 1),
          ),
          const SizedBox(height: 14),
          Text('내 레벨에 맞춰\n오늘의 학습을 만들고 있어요', style: sans(20, weight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          Text('표현 3개, 단어 10개, 문장과 퀴즈까지 · 30초 정도 걸려요', style: sans(13, color: AppColors.ink2)),
          const SizedBox(height: 18),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(
              minHeight: 4,
              color: AppColors.highlighter,
              backgroundColor: AppColors.track,
            ),
          ),
        ],
      ),
    );
  }
}

/// 맞춤 팩을 못 받아 기본 팩으로 진행할 때
class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(color: AppColors.sand, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.ink2),
          const SizedBox(width: 10),
          Expanded(child: Text('$message 오늘은 기본 학습으로 진행할 수 있어요.', style: sans(13, height: 1.45))),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_outlined, size: 16, color: AppColors.ember),
          const SizedBox(width: 4),
          Text(days == 0 ? '오늘부터 시작' : '$days일째', style: sans(13, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.step, required this.state});
  final RoutineStep step;
  final StudyState state;

  (String, String) get _texts => switch (step) {
    RoutineStep.expressions => ('오늘의 표현 ${state.pack.expressions.length}개', '3분'),
    RoutineStep.words => ('오늘의 단어 ${state.pack.words.length}개', '4분'),
    RoutineStep.speaking => ('예문 따라 말하기', '${state.pack.sentences.length}문장 · 4분'),
    RoutineStep.quiz => (
      '복습 퀴즈',
      state.pack.reviewCount == 0
          ? '${state.pack.quiz.length}문항 · 3분'
          : '오늘 ${state.pack.quiz.length - state.pack.reviewCount}문항 + 지난 복습 ${state.pack.reviewCount}문항',
    ),
  };

  double get _progress => switch (step) {
    RoutineStep.words => state.wordRatings.length / state.pack.words.length,
    RoutineStep.speaking => state.speaking.length / state.pack.sentences.length,
    RoutineStep.quiz => state.quizAnswers.length / state.pack.quiz.length,
    RoutineStep.expressions => state.expressionKnown.length / state.pack.expressions.length,
  };

  @override
  Widget build(BuildContext context) {
    final done = state.done.contains(step);
    final current = state.current == step;
    final (title, sub) = _texts;
    final number = step.index + 1;

    if (current) {
      return Material(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(routinePaths[step]!),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.highlighter, width: 2),
                  ),
                  child: Text(
                    '$number',
                    style: sans(13, weight: FontWeight.w700, color: AppColors.highlighter),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: sans(15, weight: FontWeight.w600, color: AppColors.card),
                      ),
                      const SizedBox(height: 6),
                      ThinProgress(_progress, color: AppColors.highlighter, track: const Color(0x33FFFDF8)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _progress > 0 ? '이어서' : '시작',
                  style: sans(13, weight: FontWeight.w600, color: AppColors.card),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.card, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: done ? Colors.transparent : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(routinePaths[step]!),
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (done)
                  const CircleAvatar(
                    radius: 15,
                    backgroundColor: AppColors.success,
                    child: Icon(Icons.check_rounded, size: 17, color: AppColors.card),
                  )
                else
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.lineStrong, width: 1.5),
                    ),
                    child: Text(
                      '$number',
                      style: sans(13, weight: FontWeight.w600, color: AppColors.ink2),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: done
                            ? sans(
                                15,
                                weight: FontWeight.w600,
                                color: AppColors.ink2,
                              ).copyWith(decoration: TextDecoration.lineThrough, decorationColor: AppColors.lineStrong)
                            : sans(15, weight: FontWeight.w600),
                      ),
                      if (!done) Text(sub, style: sans(12, color: AppColors.ink2)),
                    ],
                  ),
                ),
                if (done) Text('완료', style: sans(12, color: AppColors.ink2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelStrip extends StatelessWidget {
  const _LevelStrip({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final level = state.profile.overall;
    return Material(
      color: AppColors.sand,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/level-result'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(level.label, style: serif(24, weight: 600, color: AppColors.penBlue)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          level.isMax ? '최고 단계' : '다음 단계 ${level.next.label}까지',
                          style: sans(12, weight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text('${(level.progressToNext * 100).round()}%', style: sans(12, color: AppColors.ink2)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ThinProgress(level.progressToNext, height: 6, color: AppColors.penBlue, track: AppColors.sandDeep),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
