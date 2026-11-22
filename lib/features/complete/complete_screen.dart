import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/level.dart';
import '../../domain/srs.dart';
import '../settings/settings_screen.dart' show formatMinutes;

class CompleteScreen extends ConsumerStatefulWidget {
  const CompleteScreen({super.key});

  @override
  ConsumerState<CompleteScreen> createState() => _CompleteScreenState();
}

class _CompleteScreenState extends ConsumerState<CompleteScreen> {
  /// 알림 제안은 처음 완료했을 때 한 번만 (화면에 있는 동안은 계속 보여 준다)
  late final bool _askReminder = () {
    final st = ref.read(studyProvider).settings;
    return st.reminderMinutes == null && !st.reminderOffered;
  }();

  @override
  void initState() {
    super.initState();
    if (_askReminder) {
      Future.microtask(() {
        if (mounted) ref.read(studyProvider.notifier).markReminderOffered();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final delta = s.todayLevelDelta;
    final now = s.profile.overall;
    final before = delta == null ? now : Level(now.score - delta);
    final speaking = s.speakingAverage;
    final newWords = s.wordRatings.values.where((r) => r != SelfRating.know).length;
    final levelUp = before.step < now.step;
    // 축하 문구 우선순위: 레벨 업 > 최고 기록 경신 > 복귀 > 연속 마일스톤
    final streak = s.streakDays;
    final prevBest = s.previousLongest;
    final milestone = switch (streak) {
      _ when streak >= 3 && streak > prevBest && prevBest >= 3 => '최고 기록 경신! $streak일 연속',
      1 when prevBest >= 2 => '다시 시작! 최고 기록 $prevBest일까지 ${prevBest - 1}일',
      3 => '3일 연속! 작심삼일을 넘었어요',
      7 => '일주일 연속! 쉬는 날이 1개 생겼어요',
      14 => '2주 연속! 정말 대단해요',
      21 => '3주 연속! 이제 습관이에요',
      30 => '한 달 연속! 이제 영어가 일상이에요',
      50 || 100 || 200 || 365 => '$streak일 연속! 기록을 세웠어요',
      _ => null,
    };

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
                    // 불꽃(또는 레벨 업이면 새 레벨)이 톡 튀어나온다
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.elasticOut,
                      builder: (_, v, child) => Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 112,
                        height: 112,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.ink,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.sand, spreadRadius: 10)],
                        ),
                        child: levelUp
                            ? Text(now.label, style: serif(34, weight: 600, color: AppColors.highlighter))
                            : const Icon(Icons.local_fire_department_rounded, size: 46, color: AppColors.highlighter),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Center(
                    // 연속 학습일이 하나 올라가는 순간을 보여준다
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: (s.streakDays - 1).clamp(0, 99999).toDouble(), end: s.streakDays.toDouble()),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${v.round()}', style: serif(44, weight: 500, letterSpacing: -1)),
                            TextSpan(
                              text: '일 연속',
                              style: sans(22, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      levelUp ? '레벨 업! ${before.label} → ${now.label}' : milestone ?? '오늘 루틴 완료!',
                      textAlign: TextAlign.center,
                      style: sans(22, weight: FontWeight.w700, letterSpacing: -0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      '표현 ${s.pack.expressions.length}개, 단어 ${s.pack.words.length}개, 문장 ${s.spokenCount}개를 따라 했어요',
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
                            // 점수가 내려간 날은 숫자로 탓하지 않는다 (아래에 이유를 보여 준다)
                            if (delta != null && delta >= 0)
                              Text(
                                '${delta >= 0 ? '+' : ''}$delta',
                                style: sans(
                                  13,
                                  weight: FontWeight.w700,
                                  color: delta >= 0 ? AppColors.success : AppColors.error,
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
                                  width: double.infinity,
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
                  if (_askReminder) ...[const SizedBox(height: 12), const _ReminderSuggestion()],
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
                if (s.dueCount > 0)
                  OutlinedButton(
                    onPressed: () => context.pushReplacement('/review-session'),
                    child: Text('복습 카드 ${s.dueCount}장도 넘기기 · ${s.reviewMinutes}분'),
                  ),
                TextButton(onPressed: () => context.go('/review'), child: const Text('틀린 문제 다시 보기')),
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

/// 첫 완료 때: 내일 몇 시에 알려 줄지 바로 고르게 한다 (동기가 가장 높은 순간)
class _ReminderSuggestion extends ConsumerStatefulWidget {
  const _ReminderSuggestion();

  @override
  ConsumerState<_ReminderSuggestion> createState() => _ReminderSuggestionState();
}

class _ReminderSuggestionState extends ConsumerState<_ReminderSuggestion> {
  String? _message;

  Future<void> _pick(int minutes) async {
    final ok = await ref.read(studyProvider.notifier).setReminder(minutes);
    if (!mounted) return;
    setState(() => _message = ok ? '내일 ${formatMinutes(minutes)}에 알려 드릴게요.' : '알림 권한을 허용하면 아침마다 알려 드릴게요.');
  }

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('내일 몇 시에 알려 드릴까요?', style: sans(15, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (_message != null)
            Text(_message!, style: sans(14, color: AppColors.ink2))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [7 * 60 + 30, 8 * 60, 12 * 60 + 30, 21 * 60])
                  ActionChip(
                    label: Text(formatMinutes(m), style: sans(14, weight: FontWeight.w500)),
                    backgroundColor: AppColors.paper,
                    side: const BorderSide(color: AppColors.line),
                    onPressed: () => _pick(m),
                  ),
                ActionChip(
                  label: Text('괜찮아요', style: sans(14, color: AppColors.ink2)),
                  backgroundColor: AppColors.paper,
                  side: const BorderSide(color: AppColors.line),
                  onPressed: () => setState(() => _message = '알림은 설정에서 언제든 켤 수 있어요.'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
