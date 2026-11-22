import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import 'study_controller.dart';

const routinePaths = {
  RoutineStep.expressions: '/expressions',
  RoutineStep.words: '/words',
  RoutineStep.speaking: '/speaking',
  RoutineStep.quiz: '/quiz',
};

/// 루틴 단계 이름
String stepTitle(RoutineStep step, StudyState s) => switch (step) {
  RoutineStep.expressions => '오늘의 표현 ${s.pack.expressions.length}개',
  RoutineStep.words => '오늘의 단어 ${s.pack.words.length}개',
  RoutineStep.speaking => '예문 따라 말하기',
  RoutineStep.quiz => '복습 퀴즈',
};

/// 단계별 예상 시간(분)
int stepMinutes(RoutineStep step) => switch (step) {
  RoutineStep.expressions => 3,
  RoutineStep.words => 4,
  RoutineStep.speaking => 4,
  RoutineStep.quiz => 3,
};

/// 남은 단계 예상 시간(분)
int remainingMinutes(StudyState s) =>
    RoutineStep.values.where((e) => !s.done.contains(e)).fold(0, (sum, e) => sum + stepMinutes(e));

String _doneTitle(RoutineStep step) => switch (step) {
  RoutineStep.expressions => '표현 학습 완료!',
  RoutineStep.words => '단어 학습 완료!',
  RoutineStep.speaking => '말하기 완료!',
  RoutineStep.quiz => '퀴즈 완료!',
};

/// 다음에 할 루틴 단계 (모두 끝났으면 null)
RoutineStep? nextStep(StudyState s) {
  for (final step in RoutineStep.values) {
    if (!s.done.contains(step)) return step;
  }
  return null;
}

/// 루틴 단계를 끝낸다. 홈으로 돌아가지 않고 다음 단계로 바로 이어갈 수 있게 묻는다.
/// 모두 끝났으면 완료 화면으로 간다.
Future<void> finishStep(BuildContext context, WidgetRef ref, RoutineStep step) async {
  ref.read(studyProvider.notifier).complete(step);
  final s = ref.read(studyProvider);
  if (s.allDone) {
    context.pushReplacement('/complete');
    return;
  }
  final next = nextStep(s)!;
  final remaining = RoutineStep.values.where((e) => !s.done.contains(e)).length;
  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.card,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_doneTitle(step), style: sans(20, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '남은 단계 $remaining개 · 약 ${remainingMinutes(s)}분 · 다음은 ${stepTitle(next, s)}',
              style: sans(14, color: AppColors.ink2),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('이어서 하기')),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('나중에 할게요')),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  go == true ? context.pushReplacement(routinePaths[next]!) : context.pop();
}
