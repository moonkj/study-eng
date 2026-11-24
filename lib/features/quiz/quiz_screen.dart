import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/study_shortcuts.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../domain/pack_prep.dart';
import 'recall_input.dart';

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> with StudyScreenGuard {
  // 끝낸 단계를 다시 보면 처음부터
  late int _index = ref.read(studyProvider).done.contains(RoutineStep.quiz)
      ? 0
      : ref.read(studyProvider).quizAnswers.length.clamp(0, ref.read(studyProvider).pack.quiz.length - 1);

  void _next() {
    final total = ref.read(studyProvider).pack.quiz.length;
    if (_index >= total - 1) {
      finishStep(context, ref, RoutineStep.quiz);
      return;
    }
    setState(() => _index++);
  }

  /// 회상형 문제에서 이번에 쓴 답 (문제 번호별, 화면을 다시 열면 비어 있다)
  final _typed = <int, String>{};

  /// 회상형 문제: 맞으면 0(정답 위치), 틀리면 1 을 답으로 기록한다
  void _answerRecall(String typed) {
    final item = ref.read(studyProvider).pack.quiz[_index];
    _typed[_index] = typed.trim();
    _answer(isRecallCorrect(item, typed) ? item.answerIndex : 1);
  }

  /// 회상형 문제를 스스로 채점: 복습 일정에는 반영하고 점수에서는 뺀다
  void _selfGrade(bool correct) {
    final s = ref.read(studyProvider);
    final item = s.pack.quiz[_index];
    if (s.quizAnswers.containsKey(_index)) return;
    ref.read(studyProvider.notifier).answerQuiz(_index, correct ? item.answerIndex : 1, selfGraded: true);
    correct ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
  }

  void _answer(int choice) {
    final s = ref.read(studyProvider);
    final item = s.pack.quiz[_index];
    if (s.quizAnswers.containsKey(_index) || (!item.isRecall && choice >= item.choices.length)) return;
    ref.read(studyProvider.notifier).answerQuiz(_index, choice);
    choice == item.answerIndex ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final quiz = s.pack.quiz;
    // 팩이 바뀌어 개수가 줄었으면 범위 안으로
    if (_index >= quiz.length) _index = quiz.length - 1;
    final item = quiz[_index];
    final picked = s.quizAnswers[_index];
    final answered = picked != null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        // iPad 하드웨어 키보드: 1~4 보기 선택, Enter 다음, Esc 닫기
        child: StudyShortcuts(
          bindings: {
            if (!item.isRecall)
              for (final (i, key) in [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
              ].indexed)
                SingleActivator(key): () => _answer(i),
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (answered) _next();
            },
            const SingleActivator(LogicalKeyboardKey.escape): () => popOrHome(context),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => popOrHome(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: _Segments(state: s)),
                    const SizedBox(width: 12),
                    Text(
                      '${_index + 1}/${quiz.length}',
                      style: sans(13, weight: FontWeight.w600, color: context.colors.ink2),
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
                              color: context.colors.ink,
                              background: context.colors.sand,
                            )
                          : Tag('오늘 배운 내용'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      item.isRecall ? '첫 글자를 보고 빈칸에 들어갈 영어를 써 주세요' : '알맞은 영어 문장을 골라주세요',
                      style: sans(15, weight: FontWeight.w500, color: context.colors.ink2),
                    ),
                    const SizedBox(height: 8),
                    Text(item.prompt, style: sans(26, weight: FontWeight.w700, letterSpacing: -0.5, height: 1.35)),
                    const SizedBox(height: 22),
                    if (item.isRecall)
                      RecallQuestion(
                        key: ValueKey(item.id),
                        item: item,
                        answered: answered,
                        typed: _typed[_index],
                        onSubmit: _answerRecall,
                        onGiveUp: () => _answer(1),
                        onSelfGrade: _selfGrade,
                      )
                    else
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
                          onTap: answered ? null : () => _answer(i),
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
              AnimatedSize(
                duration: motion(context, AppMotion.base),
                curve: Curves.easeOutCubic,
                child: answered
                    ? _Feedback(
                        item: item,
                        mine: picked == item.answerIndex
                            ? null
                            : item.isRecall
                            ? (_typed[_index]?.isEmpty ?? true ? null : _typed[_index])
                            : item.choices[picked],
                        // 회상형은 단어만이 아니라 빈칸을 채운 문장 전체를 읽어 준다
                        onListen: () => ref.read(sayProvider)(
                          item.isRecall
                              ? item.clue!.replaceFirst(blankFor(item.choices[0]), item.choices[0])
                              : item.choices[item.answerIndex],
                        ),
                        correct: picked == item.answerIndex,
                        onNext: _next,
                        nextLabel: _index < quiz.length - 1
                            ? '다음 문제'
                            // 다른 단계가 남았으면 결과 화면이 아니라 다음 단계를 묻는다
                            : s.done.length >= RoutineStep.values.length - 1
                            ? '결과 보기'
                            : '퀴즈 마치기',
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
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
            child: Semantics(
              label:
                  '${i + 1}번 ${!state.quizAnswers.containsKey(i)
                      ? '아직'
                      : state.quizAnswers[i] == quiz[i].answerIndex
                      ? '정답'
                      : '오답'}',
              child: Container(
                // 색만으로 구분하지 않도록 오답 칸은 더 두껍게
                height: state.quizAnswers.containsKey(i) && state.quizAnswers[i] != quiz[i].answerIndex ? 8 : 4,
                margin: EdgeInsets.only(right: i == quiz.length - 1 ? 0 : 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: !state.quizAnswers.containsKey(i)
                      ? context.colors.track
                      : state.quizAnswers[i] == quiz[i].answerIndex
                      ? context.colors.success
                      : context.colors.error,
                ),
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
      _Status.correct => (context.colors.successTint, context.colors.success, 2.0),
      _Status.wrong => (context.colors.errorTint, context.colors.error, 2.0),
      _ => (context.colors.card, context.colors.line, 1.0),
    };
    // 답한 뒤 나머지 보기: 흐리게(Opacity) 대신 글자색으로 구분해 대비를 지킨다
    return AnimatedContainer(
      duration: motion(context, AppMotion.fast),
      child: Semantics(
        button: true,
        enabled: onTap != null,
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
                      child: englishSemantics(
                        text,
                        Text(
                          text,
                          style:
                              serif(
                                18,
                                color: status == _Status.wrong || status == _Status.dim
                                    ? context.colors.ink2
                                    : context.colors.ink,
                              ).copyWith(
                                decoration: status == _Status.wrong ? TextDecoration.lineThrough : null,
                                decorationColor: context.colors.error,
                              ),
                        ),
                      ),
                    ),
                    if (status == _Status.correct)
                      Text(
                        '정답',
                        style: sans(12, weight: FontWeight.w700, color: context.colors.success),
                      ),
                    if (status == _Status.wrong)
                      Text(
                        '내 답',
                        style: sans(12, weight: FontWeight.w700, color: context.colors.error),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.item,
    required this.mine,
    required this.correct,
    required this.onNext,
    required this.onListen,
    required this.nextLabel,
  });
  final QuizItem item;

  /// 틀렸을 때 내 답 (고른 보기 또는 쓴 답, 없으면 null)
  final String? mine;
  final bool correct;
  final VoidCallback onListen;
  final VoidCallback onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // 스크린리더가 결과를 바로 읽어 주도록
      // 결과 시트가 뜨면 안의 글(정답 여부, 답, 해설)을 스크린리더가 이어서 읽는다
      liveRegion: true,
      child: ConstrainedBox(
        // 해설이 길거나 글씨가 커도 화면을 다 덮지 않도록
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: _sheet(context),
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    final answer = item.choices[item.answerIndex];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(22, 22, 22, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        border: Border(top: BorderSide(color: context.colors.line)),
        boxShadow: [
          BoxShadow(color: context.colors.sheetShadow, offset: Offset(0, -12), blurRadius: 30, spreadRadius: -20),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: correct ? context.colors.successTint : context.colors.errorTint,
                  child: Icon(
                    correct ? Icons.check_rounded : Icons.priority_high_rounded,
                    size: 16,
                    color: correct ? context.colors.success : context.colors.error,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(correct ? '정답이에요!' : '아쉬워요. 정답과 이 부분이 달라요', style: sans(16, weight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!correct) ...[
              // 내 답(취소선) → 정답(굵게) 을 나란히 보여 차이가 바로 보이게
              if (mine != null)
                Text(
                  mine!,
                  style: serif(16, color: context.colors.ink2).copyWith(decoration: TextDecoration.lineThrough),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: englishSemantics('정답 $answer', Text(answer, style: serif(18, weight: 600)))),
                  RoundIconButton(icon: Icons.volume_up_rounded, label: '정답 듣기', onPressed: onListen),
                ],
              ),
              const SizedBox(height: 10),
            ] else if (correct) ...[
              Row(
                children: [
                  Expanded(child: englishSemantics('정답 $answer', Text(answer, style: serif(18, weight: 600)))),
                  RoundIconButton(icon: Icons.volume_up_rounded, label: '정답 듣기', onPressed: onListen),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Text(item.explanation, style: sans(14, height: 1.65, color: context.colors.inkSoft)),
            if (!correct) ...[
              const SizedBox(height: 8),
              Text('틀린 표현은 복습 카드로 곧 다시 만나요.', style: sans(12, color: context.colors.ink2)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onNext, child: Text(nextLabel)),
            ),
          ],
        ),
      ),
    );
  }
}
