import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/study_controller.dart';
import '../../core/audio/tts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/grade_source.dart';
import '../../data/toeic.dart';
import '../../domain/speech_score.dart';
import '../../domain/toeic_feedback.dart';
import '../speaking/speech_input.dart';
import 'timed_listen.dart';
import 'toeic_task.dart';

part 'toeic_phase_timer.dart';
part 'toeic_result.dart';

/// 질문 하나에 대한 내 답
class TurnOutcome {
  const TurnOutcome({required this.turn, required this.transcript, required this.seconds});
  final ToeicTurn turn;
  final String transcript;

  /// 실제로 말한 시간(초): 답하기 시작부터 마지막으로 말이 들린 때까지
  final int seconds;
}

/// 기기에서 계산한 점수
int offlineTurnScore(ToeicTask task, TurnOutcome o) => offlineScore(
  type: task.type,
  transcript: o.transcript,
  limitSeconds: o.turn.speakSeconds,
  reference: task.type == ToeicTaskType.readAloud ? o.turn.reference : null,
  keyPhrases: task.keyPhrases,
);

/// 묶음 결과를 저장 형식으로 ([grades] 가 모두 있으면 서버 점수)
ToeicTaskRecord recordOf(ToeicTask task, List<TurnOutcome> outcomes, [Map<int, GradeResult> grades = const {}]) {
  final graded = outcomes.isNotEmpty && outcomes.every((o) => grades.containsKey(o.turn.number));
  final scores = [for (final o in outcomes) graded ? grades[o.turn.number]!.percent : offlineTurnScore(task, o)];
  return ToeicTaskRecord(
    type: task.type,
    score: scores.isEmpty ? 0 : (scores.reduce((a, b) => a + b) / scores.length).round(),
    graded: graded,
    words: outcomes.fold(0, (s, o) => s + wordCount(o.transcript)),
    seconds: outcomes.fold(0, (s, o) => s + o.seconds),
    limit: task.limitSeconds,
  );
}

/// 서버에 채점을 맡긴다 (서버가 없거나 말한 것이 없으면 null)
Future<GradeResult?> gradeTurn(GradeSource? source, ToeicTask task, TurnOutcome o, ToeicTarget target) async {
  if (source == null || o.transcript.trim().isEmpty) return null;
  return source.grade(
    task: task.type,
    target: target.label,
    prompt: o.turn.gradePrompt,
    reference: o.turn.reference,
    transcript: o.transcript,
    seconds: o.seconds,
    limitSeconds: o.turn.speakSeconds,
  );
}

/// 써 보면 좋은 표현 (보여 줄 문장, 썼는지 확인할 부분)
typedef Suggestion = ({String text, String check});

enum _Phase { intro, reading, cue, prep, speak, finishing, result }

/// 토스 문항 하나를 시험처럼 진행하는 화면 조각:
/// 안내 → "Begin preparing now" + 준비 시간 → "Begin speaking now" + 답하기 시간(듣고 받아 적기) → 결과
///
/// [exam] 이면 결과 없이 바로 [onComplete] 를 부른다 (모의고사).
class ToeicTaskView extends ConsumerStatefulWidget {
  const ToeicTaskView({
    super.key,
    required this.task,
    required this.onComplete,
    this.exam = false,
    this.autoStart = false,
    this.suggestions = const [],
  });

  final ToeicTask task;
  final void Function(List<TurnOutcome> outcomes, ToeicTaskRecord record) onComplete;
  final bool exam;

  /// 안내를 잠깐 보여 준 뒤 저절로 시작 (모의고사 두 번째 문항부터)
  final bool autoStart;
  final List<Suggestion> suggestions;

  @override
  ConsumerState<ToeicTaskView> createState() => _ToeicTaskViewState();
}

class _ToeicTaskViewState extends ConsumerState<ToeicTaskView> {
  ToeicTask get task => widget.task;

  _Phase _phase = _Phase.intro;
  int _turn = 0;
  int _total = 0;
  int _remaining = 0;
  Timer? _timer;

  /// 진행을 다시 시작하거나 화면을 나가면 늘려서, 기다리던 이전 흐름을 멈춘다
  int _run = 0;

  TimedListen? _listen;
  String _live = '';
  String? _micError;
  int _speakElapsed = 0;
  int _lastHeardAt = 0;

  final _outcomes = <TurnOutcome>[];
  final _grades = <int, GradeResult>{};
  final _gradeErrors = <int, String>{};
  final _grading = <int>{};

  /// 결과에서 펼친 질문 번호 (하나만 펼친다, 처음엔 모두 접힘)
  int? _openTurn;

  /// '고친 걸로 다시 말하기' 로 다시 할 때 화면에 띄워 둘 고칠 것
  _FocusFix? _focus;

  late final Speaker _speaker;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _speaker = ref.read(speakerProvider);
    if (widget.autoStart) {
      final run = _run;
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && run == _run && _phase == _Phase.intro) _start();
      });
    }
  }

  @override
  void dispose() {
    _run++;
    _timer?.cancel();
    _listen?.stop();
    _speaker.stop();
    _scroll.dispose();
    super.dispose();
  }

  bool _alive(int run) => mounted && run == _run;

  Future<void> _say(String text) => ref.read(sayProvider)(text);

  /// [seconds] 동안 1초씩 세고 끝나면 [then]
  void _countdown(_Phase phase, int seconds, void Function() then) {
    _timer?.cancel();
    setState(() {
      _phase = phase;
      _total = seconds;
      _remaining = seconds;
    });
    final run = _run;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_alive(run)) return t.cancel();
      setState(() {
        _remaining--;
        if (phase == _Phase.speak) _speakElapsed++;
      });
      _timeCue(phase);
      if (_remaining <= 0) {
        t.cancel();
        then();
      }
    });
  }

  /// 남은 10초·5초: 스크린리더로 따로 알리고, 5초에는 진동도 (live region 에는 단계 이름만 있다)
  void _timeCue(_Phase phase) {
    final message = _remainingAnnouncement(phase, _remaining, _total);
    if (message == null) return;
    SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr);
    if (_remaining == _urgentAt) HapticFeedback.selectionClick();
  }

  void _start() {
    final run = ++_run;
    _outcomes.clear();
    _grades.clear();
    _gradeErrors.clear();
    _grading.clear();
    _micError = null;
    if (task.readSeconds > 0) {
      _countdown(_Phase.reading, task.readSeconds, () => _runTurn(run, 0));
    } else {
      _runTurn(run, 0);
    }
  }

  Future<void> _runTurn(int run, int i) async {
    if (!_alive(run)) return;
    final turn = task.turns[i];
    setState(() {
      _turn = i;
      _phase = _Phase.cue;
      _live = '';
    });
    for (final text in turn.speakBefore) {
      await _say(text);
      if (!_alive(run)) return;
    }
    await _say('Begin preparing now.');
    if (!_alive(run)) return;
    _countdown(_Phase.prep, turn.prepSeconds, () => _beginSpeaking(run));
  }

  Future<void> _beginSpeaking(int run) async {
    if (!_alive(run)) return;
    _timer?.cancel();
    setState(() => _phase = _Phase.cue);
    await _say('Begin speaking now.');
    if (!_alive(run)) return;
    await _speaker.stop();
    // 소리를 놓쳐도 답하기 시작을 알 수 있게
    HapticFeedback.mediumImpact();
    final turn = task.turns[_turn];
    _speakElapsed = 0;
    _lastHeardAt = 0;
    final listen = _listen = TimedListen(
      ref.read(speechInputProvider),
      expected: turn.reference ?? turn.question ?? '',
      onText: (t) {
        if (!_alive(run)) return;
        setState(() {
          if (t != _live) _lastHeardAt = _speakElapsed + 1;
          _live = t;
        });
      },
      onError: (m) {
        if (_alive(run)) setState(() => _micError = m);
      },
    );
    listen.start();
    _countdown(_Phase.speak, turn.speakSeconds, () => _endSpeaking(run));
  }

  Future<void> _endSpeaking(int run) async {
    if (!_alive(run) || _phase != _Phase.speak) return;
    _timer?.cancel();
    HapticFeedback.lightImpact();
    setState(() => _phase = _Phase.finishing);
    final heard = await (_listen?.stop() ?? Future.value(_live));
    _listen = null;
    if (!_alive(run)) return;
    final turn = task.turns[_turn];
    final text = heard.trim().isEmpty ? _live.trim() : heard.trim();
    final seconds = text.isEmpty ? 0 : _lastHeardAt.clamp(1, turn.speakSeconds);
    _outcomes.add(TurnOutcome(turn: turn, transcript: text, seconds: seconds));
    if (_turn + 1 < task.turns.length) {
      _runTurn(run, _turn + 1);
      return;
    }
    if (widget.exam) {
      widget.onComplete(List.of(_outcomes), recordOf(task, _outcomes));
      return;
    }
    setState(() => _phase = _Phase.result);
    _toTop();
    _gradeAll(run);
  }

  Future<void> _gradeAll(int run) async {
    final source = ref.read(gradeSourceProvider);
    if (source == null) return;
    final target = ref.read(studyProvider).toeicTarget;
    for (final o in List.of(_outcomes)) {
      if (o.transcript.isEmpty) continue;
      final n = o.turn.number;
      setState(() => _grading.add(n));
      try {
        final g = await gradeTurn(source, task, o, target);
        if (!_alive(run)) return;
        setState(() {
          if (g != null) _grades[n] = g;
          _grading.remove(n);
        });
      } catch (e) {
        if (!_alive(run)) return;
        setState(() {
          _gradeErrors[n] = e is Exception ? '$e'.replaceFirst('PackFetchException: ', '') : '채점을 받지 못했어요.';
          _grading.remove(n);
        });
      }
    }
  }

  /// 연습: 준비를 일찍 끝내기 / 다 말했으면 일찍 끝내기
  void _skipPrep() {
    if (_phase == _Phase.prep) _beginSpeaking(_run);
    if (_phase == _Phase.reading) {
      _timer?.cancel();
      _runTurn(_run, 0);
    }
  }

  /// 같은 문항을 처음부터 다시. [focus] 가 있으면 다시 하는 동안 고칠 것을 띄워 둔다.
  void _retry({_FocusFix? focus}) {
    _focus = focus;
    _openTurn = null;
    _run++;
    _timer?.cancel();
    _listen?.stop();
    _listen = null;
    _speaker.stop();
    setState(() {
      _phase = _Phase.intro;
      _turn = 0;
    });
    _toTop();
    _start();
  }

  /// 결과·다시 하기로 바뀌면 맨 위(요약 띠·타이머)부터 보이게
  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _next() => widget.onComplete(List.of(_outcomes), recordOf(task, _outcomes, _grades));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.md, AppSpace.xxl, AppSpace.lg),
            children: _phase == _Phase.result ? _resultChildren(context) : _liveChildren(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.sm, AppSpace.xxl, AppSpace.xl),
          child: _bottom(context),
        ),
      ],
    );
  }

  List<Widget> _liveChildren(BuildContext context) {
    final turn = task.turns[_turn];
    final started = _phase != _Phase.intro;
    return [
      Text(task.title, style: AppType.title2(weight: FontWeight.w700)),
      const SizedBox(height: AppSpace.xs),
      Text(task.directionsKo, style: AppType.callout(color: context.colors.ink2, height: 1.5)),
      const SizedBox(height: AppSpace.lg),
      if (started) ...[
        _PhaseTimer(phase: _phase, remaining: _remaining, total: _total, number: turn.number),
        const SizedBox(height: AppSpace.lg),
      ],
      if (_focus != null && !widget.exam) ...[
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: context.colors.penBlueTint,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '이번에 고칠 것',
                style: AppType.caption(weight: FontWeight.w600, color: context.colors.penBlue),
              ),
              const SizedBox(height: AppSpace.xs),
              _FixLine(fix: _focus!),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
      ],
      ..._content(context),
      if (started && task.turns.length > 1 && turn.question != null && turn.showQuestion) ...[
        const SizedBox(height: AppSpace.lg),
        PaperCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: englishSemantics(
            turn.question!,
            Text(turn.question!, style: AppType.enBody(weight: 500, height: 1.35)),
          ),
        ),
      ],
      if (started && task.type == ToeicTaskType.info) ...[
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            Icon(Icons.headphones_rounded, size: 18, color: context.colors.penBlue),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text('질문 ${turn.number - 7}/3 · 듣고 답해요', style: AppType.caption(color: context.colors.ink2)),
            ),
          ],
        ),
      ],
      if (widget.suggestions.isNotEmpty && task.suggestExpressions && !widget.exam) ...[
        const SizedBox(height: AppSpace.lg),
        _SuggestionCard(suggestions: widget.suggestions),
      ],
      if (_phase == _Phase.speak || _phase == _Phase.finishing) ...[
        const SizedBox(height: AppSpace.lg),
        PaperCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hearing_rounded, color: context.colors.penBlue),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: _micError != null
                    ? Text(_micError!, style: AppType.callout(color: context.colors.error, height: 1.5))
                    : _live.isEmpty
                    ? Text('듣고 있어요. 시간이 끝날 때까지 이어서 말해 보세요.', style: AppType.callout(height: 1.5))
                    : Text('"$_live"', style: AppType.enBody(italic: true, height: 1.4)),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  /// 문항 내용 (글·사진·상황·표)
  List<Widget> _content(BuildContext context) {
    final turn = task.turns.first;
    return [
      if (task.passage != null)
        PaperCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: englishSemantics(
            task.passage!,
            Text(task.passage!, style: AppType.enTitle(weight: 400, height: 1.45)),
          ),
        ),
      if (task.picture != null) ToeicPicture(item: task.picture!),
      if (task.setting != null)
        Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(color: context.colors.sand, borderRadius: BorderRadius.circular(AppRadius.card)),
          child: englishSemantics(task.setting!, Text(task.setting!, style: AppType.enCallout(height: 1.45))),
        ),
      if (task.info != null) InfoTableView(table: task.info!.table),
      if (task.turns.length == 1 && turn.question != null) ...[
        const SizedBox(height: AppSpace.xs),
        PaperCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: englishSemantics(
            turn.question!,
            Text(turn.question!, style: AppType.enBody(weight: 500, height: 1.35)),
          ),
        ),
      ],
    ];
  }

  Widget _bottom(BuildContext context) {
    switch (_phase) {
      case _Phase.intro:
        return widget.autoStart
            ? Text(
                '곧 시작해요',
                textAlign: TextAlign.center,
                style: AppType.callout(color: context.colors.ink2),
              )
            : FilledButton(onPressed: _start, child: const Text('시작'));
      case _Phase.reading:
      case _Phase.prep:
        return widget.exam
            ? const SizedBox(height: AppSpace.huge)
            : OutlinedButton(onPressed: _skipPrep, child: Text(_phase == _Phase.reading ? '다 읽었어요' : '준비 끝 · 바로 말하기'));
      case _Phase.speak:
        return widget.exam
            ? const SizedBox(height: AppSpace.huge)
            : OutlinedButton(onPressed: () => _endSpeaking(_run), child: const Text('다 말했어요'));
      case _Phase.cue:
      case _Phase.finishing:
        return const SizedBox(height: AppSpace.huge);
      case _Phase.result:
        final summary = _summary(ref.read(studyProvider).toeicTarget);
        // 목표 미달이거나 말한 시간이 짧으면 같은 문항을 고쳐서 다시 말하기가 주 버튼
        if (summary.suggestRetry) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: _next, child: const Text('다음')),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => _retry(focus: summary.fix),
                  child: const Text('고친 걸로 다시 말하기'),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => _retry(focus: summary.fix),
                child: const Text('다시 하기'),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              flex: 2,
              child: FilledButton(onPressed: _next, child: const Text('다음')),
            ),
          ],
        );
    }
  }

  _ResultSummary _summary(ToeicTarget target) =>
      _ResultSummary.of(task, _outcomes, _grades, target, grading: _grading.isNotEmpty);

  /// 따라 할 답: 다듬은 답이 있으면 그것, 없으면 목표 단계 모범 답안(문장 읽기는 원문)
  List<_ShadowAnswer> get _shadowAnswers => [
    for (final o in _outcomes)
      (
        number: o.turn.number,
        text: (_grades[o.turn.number]?.improved ?? '').trim().isNotEmpty
            ? _grades[o.turn.number]!.improved
            : o.turn.model,
      ),
  ];

  List<Widget> _resultChildren(BuildContext context) {
    final say = ref.read(sayProvider);
    final target = ref.watch(studyProvider.select((s) => s.toeicTarget));
    final summary = _summary(target);
    final improved = _outcomes.any((o) => (_grades[o.turn.number]?.improved ?? '').trim().isNotEmpty);
    return [
      Text(task.title, style: AppType.title2(weight: FontWeight.w700)),
      const SizedBox(height: AppSpace.md),
      // ① 요약 띠
      _SummaryStrip(
        summary: summary,
        target: target,
        grading: _grading.isNotEmpty,
        readAloud: task.type == ToeicTaskType.readAloud,
      ),
      // ② 질문별 카드 (접어 둠)
      for (final o in _outcomes) ...[
        const SizedBox(height: AppSpace.md),
        _TurnCard(
          key: ValueKey('turn-${o.turn.number}'),
          task: task,
          outcome: o,
          grade: _grades[o.turn.number],
          gradeError: _gradeErrors[o.turn.number],
          grading: _grading.contains(o.turn.number),
          suggestions: task.suggestExpressions ? widget.suggestions : const [],
          onPlay: (t) => say(t),
          expanded: _openTurn == o.turn.number,
          onToggle: () => setState(() => _openTurn = _openTurn == o.turn.number ? null : o.turn.number),
        ),
      ],
      // ③ 다듬은 답 문장 단위 따라 하기 (채점이 오는 중이면 기다렸다가 다듬은 답으로)
      if (_grading.isEmpty) ...[
        const SizedBox(height: AppSpace.lg),
        _ShadowingCard(
          key: ValueKey('shadow-$improved'),
          title: improved
              ? '다듬은 답 따라 하기'
              : task.type == ToeicTaskType.readAloud
              ? '원문 따라 읽기'
              : '모범 답안 따라 하기',
          answers: _shadowAnswers,
          say: say,
        ),
      ],
      // 문항 다시 보기 (글·사진·표와 요령)
      const SizedBox(height: AppSpace.xl),
      Text(
        '문항 다시 보기',
        style: AppType.caption(weight: FontWeight.w600, color: context.colors.ink2),
      ),
      const SizedBox(height: AppSpace.sm),
      ..._content(context),
      if (task.tips.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        for (final t in task.tips)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text('· $t', style: AppType.callout(color: context.colors.inkSoft, height: 1.5)),
          ),
      ],
      if (task.picture != null && task.picture!.vocab.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Text(
          '사진 단어 · ${task.picture!.vocab.map((v) => '${v.en} ${v.ko}').join(' · ')}',
          style: AppType.callout(color: context.colors.inkSoft, height: 1.5),
        ),
      ],
    ];
  }
}

/// 사진 (파일이 없으면 자리 표시)
class ToeicPicture extends StatelessWidget {
  const ToeicPicture({super.key, required this.item});
  final PictureItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.asset(
              item.file,
              fit: BoxFit.cover,
              semanticLabel: item.place.isEmpty ? '문항 사진' : '사진: ${item.place}',
              errorBuilder: (context, _, _) => Container(
                color: context.colors.sand,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 40, color: context.colors.ink2),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      item.place.isEmpty ? '사진을 불러오지 못했어요' : item.place,
                      style: AppType.caption(color: context.colors.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (item.credit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              item.credit,
              style: AppType.micro(weight: FontWeight.w400, color: context.colors.ink2),
            ),
          ),
      ],
    );
  }
}

/// 표 보고 답하기의 표
class InfoTableView extends StatelessWidget {
  const InfoTableView({super.key, required this.table});
  final InfoTable table;

  @override
  Widget build(BuildContext context) {
    final cell = AppType.enCaption(height: 1.3);
    return PaperCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(table.title, textAlign: TextAlign.center, style: AppType.enBody(weight: 600)),
          if (table.subtitle != null)
            Text(
              table.subtitle!,
              textAlign: TextAlign.center,
              style: AppType.enCaption(color: context.colors.ink2),
            ),
          const SizedBox(height: AppSpace.sm),
          Table(
            border: TableBorder.all(color: context.colors.line),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              if (table.columns.isNotEmpty)
                TableRow(
                  decoration: BoxDecoration(color: context.colors.sand),
                  children: [
                    for (final c in table.columns)
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.sm),
                        child: Text(c, style: cell.copyWith(fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              for (final r in table.rows)
                TableRow(
                  children: [
                    for (var i = 0; i < (table.columns.isEmpty ? r.length : table.columns.length); i++)
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.sm),
                        child: Text(i < r.length ? r[i] : '', style: cell),
                      ),
                  ],
                ),
            ],
          ),
          for (final n in table.notes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(n, style: AppType.enCaption(italic: true, color: context.colors.ink2)),
            ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestions});
  final List<Suggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(color: context.colors.penBlueTint, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '써 보면 좋은 표현',
            style: AppType.caption(weight: FontWeight.w600, color: context.colors.penBlue),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final s in suggestions) Text(s.text, style: AppType.enCallout(height: 1.4)),
        ],
      ),
    );
  }
}
