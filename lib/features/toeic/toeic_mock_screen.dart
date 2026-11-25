import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routine_flow.dart' show popOrHome;
import '../../app/study_controller.dart';
import '../../core/audio/tts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/grade_source.dart';
import '../../data/toeic.dart';
import '../../domain/study_log.dart';
import '../../domain/toeic_feedback.dart';
import 'toeic_target.dart';
import 'toeic_task.dart';
import 'toeic_task_view.dart';

/// 토스 실전 모의고사: 11문항을 시험 순서·시간 그대로, 문항 사이 피드백 없이. 끝나면 결과 요약.
class ToeicMockScreen extends ConsumerStatefulWidget {
  const ToeicMockScreen({super.key});

  @override
  ConsumerState<ToeicMockScreen> createState() => _ToeicMockScreenState();
}

enum _Stage { intro, running, summary }

class _ToeicMockScreenState extends ConsumerState<ToeicMockScreen> {
  _Stage _stage = _Stage.intro;
  List<ToeicTask>? _tasks;
  int _index = 0;

  /// 문항 번호 → 내 답 / 채점
  final _outcomes = <int, ({ToeicTask task, TurnOutcome outcome})>{};
  final _grades = <int, Future<GradeResult?>>{};
  MockResult? _result;
  bool _saving = false;

  late final Speaker _speaker;

  @override
  void initState() {
    super.initState();
    _speaker = ref.read(speakerProvider);
  }

  @override
  void dispose() {
    _speaker.stop();
    super.dispose();
  }

  void _begin(ToeicBank bank) {
    final s = ref.read(studyProvider);
    setState(() {
      _tasks = mockTasks(mockSetFor(bank, s.now, s.toeicTarget), s.toeicTarget.tier);
      _index = 0;
      _stage = _Stage.running;
    });
  }

  void _onTaskDone(ToeicTask task, List<TurnOutcome> outcomes) {
    final source = ref.read(gradeSourceProvider);
    final target = ref.read(studyProvider).toeicTarget;
    for (final o in outcomes) {
      _outcomes[o.turn.number] = (task: task, outcome: o);
      // 채점은 다음 문항을 푸는 동안 뒤에서 (실패하면 기기 점수로)
      if (source != null) {
        _grades[o.turn.number] = gradeTurn(source, task, o, target).then<GradeResult?>((g) => g, onError: (_) => null);
      }
    }
    if (_index + 1 < _tasks!.length) {
      setState(() => _index++);
    } else {
      setState(() => _stage = _Stage.summary);
      _finish();
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final graded = <int, GradeResult>{};
    for (final e in _grades.entries) {
      final g = await e.value;
      if (g != null) graded[e.key] = g;
    }
    if (!mounted) return;
    final scores = <int?>[
      for (var n = 1; n <= 11; n++)
        if (_outcomes[n] == null)
          null
        else
          graded[n]?.percent ?? offlineTurnScore(_outcomes[n]!.task, _outcomes[n]!.outcome),
    ];
    // 문항별 원점수 (Q1~Q10 0~3, Q11 0~5): Claude 채점분만. 채점 서버가 있는데 아무 말도 안 했으면 실제 시험처럼 0점.
    final graderOn = ref.read(gradeSourceProvider) != null;
    final points = <int?>[
      for (var n = 1; n <= 11; n++)
        if (graded[n] case final g?)
          g.maxScore <= 0 ? 0 : (g.score * mockMaxPoints[n - 1] / g.maxScore).round()
        else if (graderOn && _outcomes[n] != null && _outcomes[n]!.outcome.transcript.trim().isEmpty)
          0
        else
          null,
    ];
    final s = ref.read(studyProvider);
    // 기기 점수만 있으면 등급을 내지 않는다
    final range = estimateMockLevel(points);
    final result = MockResult(
      date: dateKey(s.now),
      level: range?.label ?? '',
      target: s.toeicTarget.label,
      scores: scores,
      points: points,
      graded: range != null,
    );
    ref.read(studyProvider.notifier).recordMock(result);
    setState(() {
      _result = result;
      _saving = false;
    });
  }

  Future<bool> _confirmQuit() async {
    if (_stage != _Stage.running) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('모의고사를 그만할까요?'),
        content: const Text('지금까지 답한 것은 저장되지 않아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속하기')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('그만하기')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(toeicBankProvider);
    final done = _outcomes.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.md, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close_rounded, size: 26),
                    onPressed: () async {
                      if (await _confirmQuit() && context.mounted) popOrHome(context);
                    },
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text('토스 실전 모의고사', style: AppType.body(weight: FontWeight.w700)),
                  ),
                  if (_stage == _Stage.running)
                    Text(
                      '$done/11',
                      style: AppType.caption(weight: FontWeight.w600, color: context.colors.ink2),
                    ),
                ],
              ),
            ),
            Expanded(
              child: switch (_stage) {
                _Stage.intro =>
                  bank == null
                      ? Center(
                          child: Text('문항을 불러오지 못했어요.', style: AppType.body(color: context.colors.ink2)),
                        )
                      : _Intro(onStart: () => _begin(bank)),
                _Stage.running => ToeicTaskView(
                  key: ValueKey('mock-$_index'),
                  task: _tasks![_index],
                  exam: true,
                  autoStart: _index > 0,
                  onComplete: (outcomes, _) => _onTaskDone(_tasks![_index], outcomes),
                ),
                _Stage.summary =>
                  _saving || _result == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: AppSpace.md),
                              Text('채점하는 중', style: AppType.callout(color: context.colors.ink2)),
                            ],
                          ),
                        )
                      : _Summary(result: _result!, outcomes: _outcomes, onClose: () => popOrHome(context)),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends ConsumerWidget {
  const _Intro({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final rows = [
      ('Q1-2', '문장 읽기', '준비 45초 · 읽기 45초'),
      ('Q3-4', '사진 묘사', '준비 45초 · 답하기 30초'),
      ('Q5-7', '질문에 답하기', '준비 3초 · 15/15/30초'),
      ('Q8-10', '표 보고 답하기', '표 읽기 45초 · 준비 3초 · 15/15/30초'),
      ('Q11', '의견 말하기', '준비 45초 · 답하기 60초'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.lg, AppSpace.xxl, AppSpace.xl),
      children: [
        Text('실제 시험처럼 11문항', style: AppType.title2(weight: FontWeight.w700)),
        const SizedBox(height: AppSpace.xs),
        Text(
          '약 20분 · 문항 사이에 피드백 없이 이어서 진행해요. 조용한 곳에서 시작하세요. 목표 ${targetLabel(s.toeicTarget)}',
          style: AppType.callout(color: context.colors.ink2, height: 1.5),
        ),
        const SizedBox(height: AppSpace.lg),
        PaperCard(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm),
          child: Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(r.$1, style: AppType.callout(weight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.$2, style: AppType.callout()),
                            Text(r.$3, style: AppType.caption(color: context.colors.ink2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        FilledButton(onPressed: onStart, child: const Text('모의고사 시작')),
      ],
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.result, required this.outcomes, required this.onClose});
  final MockResult result;
  final Map<int, ({ToeicTask task, TurnOutcome outcome})> outcomes;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final target = ToeicTarget.values.firstWhere((t) => t.label == result.target, orElse: () => s.toeicTarget);
    final range = result.estimate;
    // 범위의 아래 등급이 목표 이상이면 달성, 위 등급만 닿으면 경계
    final met = range != null && meetsTarget(range.low, target);
    final edge = range != null && !met && meetsTarget(range.high, target);
    final say = ref.read(sayProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.lg, AppSpace.xxl, AppSpace.xxl),
      children: [
        PaperCard(
          elevated: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('예상 등급', style: AppType.caption(color: context.colors.ink2)),
              if (range != null)
                Text(range.label, style: AppType.enDisplay(weight: 600, color: context.colors.penBlue))
              else
                Text('채점 필요', style: AppType.enHero(weight: 600, color: context.colors.ink2)),
              Text(
                range == null
                    ? '등급은 Claude 채점으로만 계산해요. 채점 서버에 연결된 뒤 다시 보면 나와요.'
                    : met
                    ? '목표 ${target.label} 달성!'
                    : edge
                    ? '목표 ${target.label} 경계 · 한 번 더 보면 확실해져요'
                    : '목표 ${target.label}까지 조금 더',
                style: (range == null ? AppType.callout : AppType.body)(
                  weight: range == null ? FontWeight.w400 : FontWeight.w700,
                  color: range == null
                      ? context.colors.ink2
                      : met
                      ? context.colors.success
                      : context.colors.ember,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '평균 ${result.average.round()}점 · ${result.graded ? 'Claude 채점' : '기기에서 계산한 대략의 점수'}',
                style: AppType.caption(color: context.colors.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const TargetReachedCard(),
        const SizedBox(height: AppSpace.md),
        for (var n = 1; n <= 11; n++)
          if (outcomes[n] case final o?)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Q$n ${o.task.title.split(' ').skip(1).join(' ')}',
                style: AppType.callout(weight: FontWeight.w500),
              ),
              trailing: Text(
                result.scores.length >= n && result.scores[n - 1] != null ? '${result.scores[n - 1]}점' : '-',
                style: AppType.callout(weight: FontWeight.w600),
              ),
              childrenPadding: const EdgeInsets.only(bottom: AppSpace.md),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (o.outcome.turn.question != null)
                  Text(o.outcome.turn.question!, style: AppType.enCallout(weight: 500)),
                const SizedBox(height: AppSpace.xs),
                Text(
                  o.outcome.transcript.isEmpty ? '들린 말이 없어요.' : '"${o.outcome.transcript}"',
                  style: AppType.enCallout(italic: true, height: 1.4),
                ),
                Text(
                  '${o.outcome.seconds}초 / ${o.outcome.turn.speakSeconds}초 · 단어 ${wordCount(o.outcome.transcript)}개',
                  style: AppType.caption(color: context.colors.ink2),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '모범 답안',
                        style: AppType.caption(weight: FontWeight.w600, color: context.colors.ink2),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Q$n 모범 답안 듣기',
                      icon: const Icon(Icons.volume_up_rounded),
                      onPressed: () => say(o.outcome.turn.model),
                    ),
                  ],
                ),
                Text(o.outcome.turn.model, style: AppType.enCallout(height: 1.45)),
              ],
            ),
        const SizedBox(height: AppSpace.lg),
        FilledButton(onPressed: onClose, child: const Text('닫기')),
      ],
    );
  }
}
