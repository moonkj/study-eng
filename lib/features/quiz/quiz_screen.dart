import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  late int _index = ref.read(studyProvider).quizAnswers.length.clamp(0, ref.read(studyProvider).pack.quiz.length - 1);

  void _next() {
    final total = ref.read(studyProvider).pack.quiz.length;
    if (_index >= total - 1) {
      ref.read(studyProvider.notifier).complete(RoutineStep.quiz);
      final done = ref.read(studyProvider).allDone;
      done ? context.pushReplacement('/complete') : context.pop();
      return;
    }
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final quiz = s.pack.quiz;
    final item = quiz[_index];
    final picked = s.quizAnswers[_index];
    final answered = picked != null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(tooltip: '닫기', onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded)),
                  const SizedBox(width: 4),
                  Expanded(child: _Segments(state: s)),
                  const SizedBox(width: 12),
                  Text(
                    '${_index + 1}/${quiz.length}',
                    style: sans(13, weight: FontWeight.w600, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: item.isReview
                        ? Tag(
                            '복습 · ${item.reviewLabel}',
                            icon: Icons.replay_rounded,
                            color: AppColors.ink,
                            background: AppColors.sand,
                          )
                        : const Tag('오늘 배운 내용'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '알맞은 영어 문장을 골라주세요',
                    style: sans(15, weight: FontWeight.w500, color: AppColors.ink2),
                  ),
                  const SizedBox(height: 8),
                  Text(item.prompt, style: sans(26, weight: FontWeight.w700, letterSpacing: -0.5, height: 1.35)),
                  const SizedBox(height: 22),
                  for (var i = 0; i < item.choices.length; i++) ...[
                    _Choice(
                      text: item.choices[i],
                      status: !answered
                          ? _Status.idle
                          : i == item.answerIndex
                          ? _Status.correct
                          : i == picked
                          ? _Status.wrong
                          : _Status.dim,
                      onTap: answered ? null : () => ref.read(studyProvider.notifier).answerQuiz(_index, i),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: answered
                  ? _Feedback(
                      item: item,
                      correct: picked == item.answerIndex,
                      onNext: _next,
                      last: _index == quiz.length - 1,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final quiz = state.pack.quiz;
    return Row(
      children: [
        for (var i = 0; i < quiz.length; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == quiz.length - 1 ? 0 : 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: !state.quizAnswers.containsKey(i)
                    ? AppColors.track
                    : state.quizAnswers[i] == quiz[i].answerIndex
                    ? AppColors.success
                    : AppColors.error,
              ),
            ),
          ),
      ],
    );
  }
}

enum _Status { idle, correct, wrong, dim }

class _Choice extends StatelessWidget {
  const _Choice({required this.text, required this.status, this.onTap});
  final String text;
  final _Status status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, border, width) = switch (status) {
      _Status.correct => (AppColors.successTint, AppColors.success, 2.0),
      _Status.wrong => (AppColors.errorTint, AppColors.error, 2.0),
      _ => (AppColors.card, AppColors.line, 1.0),
    };
    return Opacity(
      opacity: status == _Status.dim ? 0.55 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: width),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: serif(18, color: status == _Status.wrong ? AppColors.ink2 : AppColors.ink).copyWith(
                        decoration: status == _Status.wrong ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.error,
                      ),
                    ),
                  ),
                  if (status == _Status.correct)
                    Text(
                      '정답',
                      style: sans(12, weight: FontWeight.w700, color: AppColors.success),
                    ),
                  if (status == _Status.wrong)
                    Text(
                      '내 답',
                      style: sans(12, weight: FontWeight.w700, color: AppColors.error),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.item, required this.correct, required this.onNext, required this.last});
  final QuizItem item;
  final bool correct;
  final VoidCallback onNext;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(22, 22, 22, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [BoxShadow(color: Color(0x4D3C2D14), offset: Offset(0, -12), blurRadius: 30, spreadRadius: -20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: correct ? AppColors.successTint : AppColors.errorTint,
                child: Icon(
                  correct ? Icons.check_rounded : Icons.priority_high_rounded,
                  size: 16,
                  color: correct ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(correct ? '정답이에요!' : '아깝다! 비슷한 표현이랑 헷갈렸어요', style: sans(16, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(item.explanation, style: sans(14, height: 1.65, color: AppColors.inkSoft)),
          if (!correct) ...[
            const SizedBox(height: 8),
            Text('이 문제는 내일 한 번 더 나와요.', style: sans(12, color: AppColors.ink2)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onNext, child: Text(last ? '결과 보기' : '다음 문제')),
          ),
        ],
      ),
    );
  }
}
