import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/toeic.dart';
import '../speaking/speaking_screen.dart';
import 'toeic_target.dart';
import 'toeic_task_view.dart';

/// 루틴 3단계 '토스 말하기': 오늘의 세트(문장 읽기 + 사진 묘사 + 돌아가는 묶음)를 차례로 한다.
/// 문항 모음을 쓸 수 없으면 예전 따라 말하기 화면을 보여 준다.
class ToeicDailyScreen extends ConsumerWidget {
  const ToeicDailyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(toeicDailyProvider) == null) return const SpeakingScreen();
    return const _ToeicDaily();
  }
}

class _ToeicDaily extends ConsumerStatefulWidget {
  const _ToeicDaily();

  @override
  ConsumerState<_ToeicDaily> createState() => _ToeicDailyState();
}

class _ToeicDailyState extends ConsumerState<_ToeicDaily> with StudyScreenGuard {
  late int _index = _firstUndone();

  /// 처음 토스 말하기를 할 때 고르는 목표 (설정에 아직 없으면)
  late bool _askTarget = ref.read(studyProvider).settings.toeicTarget == null;
  ToeicTarget _picked = ToeicTarget.fallback;

  int _firstUndone() {
    final s = ref.read(studyProvider);
    if (s.done.contains(RoutineStep.speaking)) return 0;
    final tasks = toeicTasksFor(ref.read(toeicDailyProvider)!, s);
    final i = tasks.indexWhere((t) => !s.today.toeic.containsKey(t.id));
    return i < 0 ? tasks.length - 1 : i;
  }

  void _next() {
    final set = ref.read(toeicDailyProvider);
    final tasks = set == null ? const [] : toeicTasksFor(set, ref.read(studyProvider));
    if (_index >= tasks.length - 1) {
      finishStep(context, ref, RoutineStep.speaking);
      return;
    }
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studyProvider);
    final set = ref.watch(toeicDailyProvider);
    if (set == null) return const SpeakingScreen();
    final tasks = toeicTasksFor(set, s);
    final task = tasks[_index.clamp(0, tasks.length - 1)];
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
              child: StudyTopBar(
                title: '토스 말하기 · 목표 ${s.toeicTarget.label}',
                index: _askTarget ? 0 : _index,
                total: tasks.length,
                trailing: _askTarget ? null : TextButton(onPressed: _next, child: const Text('건너뛰기')),
              ),
            ),
            Expanded(
              child: _askTarget
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                      children: [
                        Text('목표 점수를 골라요', style: sans(20, weight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '목표에 맞는 문항과 모범 답안으로 연습해요. 표현·단어 난이도도 맞춰져요. 설정에서 언제든 바꿀 수 있어요.',
                          style: sans(13, color: context.colors.ink2, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        PaperCard(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Material(
                            type: MaterialType.transparency,
                            child: ToeicTargetList(selected: _picked, onSelect: (t) => setState(() => _picked = t)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            ref.read(studyProvider.notifier).setToeicTarget(_picked);
                            setState(() => _askTarget = false);
                          },
                          child: Text('${_picked.label} 목표로 시작'),
                        ),
                      ],
                    )
                  : ToeicTaskView(
                      key: ValueKey('${task.id}-$_index'),
                      task: task,
                      suggestions: [for (final e in s.pack.expressions) (text: e.pattern, check: e.highlight)],
                      onComplete: (outcomes, record) {
                        ref.read(studyProvider.notifier).recordToeicTask(task.id, record);
                        _next();
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
