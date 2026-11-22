import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import '../domain/study_log.dart';
import '../core/audio/tts.dart';
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
  // 마지막 버튼을 빠르게 두 번 누른 경우: 이미 시트가 떠 있으면 무시 (전역 플래그 없이 화면 상태로 판단)
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
  // 이미 끝낸 단계를 다시 본 것이면 축하·이어가기 없이 돌아간다
  if (ref.read(studyProvider).done.contains(step)) {
    popOrHome(context);
    return;
  }
  await _finish(context, ref, step);
}

Future<void> _finish(BuildContext context, WidgetRef ref, RoutineStep step) async {
  ref.read(studyProvider.notifier).complete(step);
  final s = ref.read(studyProvider);
  if (s.allDone) {
    context.pushReplacement('/complete');
    return;
  }
  final next = nextStep(s)!;
  // 새벽 4시를 넘겨 학습일이 바뀐 상태(새로 고침을 미뤄 둔 상태)면 홈으로 가는 순간 어제 진행이 정리된다
  final stale = s.today.date != dateKey(studyDay(ref.read(clockProvider)()));
  final remaining = RoutineStep.values.where((e) => !s.done.contains(e)).length;
  final go = await showModalBottomSheet<bool>(
    context: context,
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
              stale
                  ? '날짜가 바뀌었어요. 마저 하면 어제 기록으로 남고, 지금 그만두면 어제 진행은 기록되지 않아요.'
                  : '남은 단계 $remaining개 · 약 ${remainingMinutes(s)}분 · 다음은 ${stepTitle(next, s)}',
              style: sans(14, color: AppColors.ink2),
            ),
            const SizedBox(height: 20),
            // 키보드(Enter)로도 바로 이어갈 수 있게
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('이어서 하기')),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(stale ? '오늘 걸로 새로 시작' : '나중에 할게요')),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  go == true ? context.pushReplacement(routinePaths[next]!) : popOrHome(context);
}

/// 돌아갈 화면이 없으면(웹 새로고침·바로 열기 등) 홈으로
void popOrHome(BuildContext context) => context.canPop() ? context.pop() : context.go('/');

/// 학습 화면 공통:
/// - 맞춤 팩을 기다리는 중에 들어오면 기본 팩으로 고정한다 (보는 도중 내용·개수가 바뀌지 않게)
/// - 화면을 나가면 읽어 주던 음성을 멈춘다
mixin StudyScreenGuard<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Speaker? _speaker;

  @override
  void initState() {
    super.initState();
    _speaker = ref.read(speakerProvider);
    if (ref.read(studyProvider).packLoading) {
      Future.microtask(() {
        if (mounted) ref.read(studyProvider.notifier).startWithFallback();
      });
    }
  }

  @override
  void dispose() {
    _speaker?.stop();
    super.dispose();
  }
}
