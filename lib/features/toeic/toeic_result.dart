part of 'toeic_task_view.dart';

// 토스 연습 결과 화면 (P0-4)
// ① 요약 띠(묶음 점수 · 목표 대비 · 고칠 것 1개) ② 질문별 카드(접어 둠, 하나만 펼침)
// ③ 다듬은 답 문장 단위 따라 하기 ④ 조건부 '고친 걸로 다시 말하기' 주 버튼
// 공통 ScoreBadge·Banner 가 생기면 [_LevelBadge]·[_FixLine] 을 그것으로 바꾸면 된다.

/// 다음 시도에 고칠 것 하나. [from] 이 있으면 "이 말 → 이렇게", 없으면 [to] 가 한국어 행동 안내다.
class _FocusFix {
  const _FocusFix({this.from, required this.to, this.why = ''});
  final String? from;
  final String to;
  final String why;
}

/// 말한 시간이 제한의 이 비율보다 짧으면 다시 말하기를 권한다
const _shortTimeRatio = 0.6;

/// 결과 요약 (화면에 보여 줄 값만 계산한다)
class _ResultSummary {
  const _ResultSummary({
    required this.graded,
    required this.score,
    required this.maxScore,
    required this.offline,
    required this.level,
    required this.targetMet,
    required this.fix,
    required this.shortTime,
  });

  factory _ResultSummary.of(
    ToeicTask task,
    List<TurnOutcome> outcomes,
    Map<int, GradeResult> grades,
    ToeicTarget target, {
    bool grading = false,
  }) {
    final graded = outcomes.isNotEmpty && outcomes.every((o) => grades.containsKey(o.turn.number));
    final gs = [for (final o in outcomes) ?grades[o.turn.number]];
    final sameMax = gs.isNotEmpty && gs.every((g) => g.maxScore == gs.first.maxScore);
    // 등급은 토익스피킹 등급표에 있는 값만 쓴다 (CEFR 등 다른 표기는 보여 주지 않는다)
    final levels = [
      for (final g in gs)
        if (toeicLevelIndex(g.level) >= 0) g.level.toUpperCase(),
    ]..sort((a, b) => toeicLevelIndex(a).compareTo(toeicLevelIndex(b)));
    final shortTime = outcomes.any((o) => o.seconds < o.turn.speakSeconds * _shortTimeRatio);
    final record = recordOf(task, outcomes, grades);
    return _ResultSummary(
      graded: graded,
      score: graded && sameMax ? gs.fold<int>(0, (s, g) => s + g.score) / gs.length : null,
      maxScore: graded && sameMax ? gs.first.maxScore : null,
      offline: record.score,
      level: graded && levels.isNotEmpty ? levels.first : null,
      targetMet: graded ? gs.every((g) => g.targetMet ?? meetsTarget(g.level, target)) : null,
      fix: _pickFix(task, outcomes, grades, grading: grading),
      shortTime: shortTime,
    );
  }

  /// 모두 서버 채점을 받았는지 (아니면 기기에서 센 대략의 점수만)
  final bool graded;

  /// 서버 점수 평균과 만점 (만점이 다른 문항이 섞이면 null → 백분율로)
  final double? score;
  final int? maxScore;

  /// 0~100 평균 (모두 서버 채점이면 서버 점수, 아니면 기기에서 센 점수)
  final int offline;

  /// 가장 낮은 문항의 토익스피킹 등급 (서버 채점일 때만)
  final String? level;
  final bool? targetMet;
  final _FocusFix? fix;
  final bool shortTime;

  /// '고친 걸로 다시 말하기' 를 주 버튼으로 올릴지: 목표 미달이거나 말한 시간이 짧았을 때
  bool get suggestRetry => targetMet == false || shortTime;

  String get scoreText {
    final s = score, m = maxScore;
    if (s == null || m == null) return '$offline점';
    return '${s == s.roundToDouble() ? s.toInt() : s.toStringAsFixed(1)}/$m';
  }
}

/// 고칠 것 하나 고르기: 가장 낮은 점수 문항의 서버 지적 → 말한 시간 → 핵심 표현 → 문장 읽기에서 안 들린 단어
_FocusFix? _pickFix(ToeicTask task, List<TurnOutcome> outcomes, Map<int, GradeResult> grades, {bool grading = false}) {
  final byScore = [for (final o in outcomes) ?grades[o.turn.number]]..sort((a, b) => a.percent.compareTo(b.percent));
  for (final g in byScore) {
    if (g.fixes.isNotEmpty) {
      final f = g.fixes.first;
      return _FocusFix(from: f.from, to: f.to, why: f.whyKo);
    }
  }
  // 채점이 오는 중이면 기기 판단으로 먼저 채우지 않는다 (도착하면 바뀌어 헷갈리므로)
  if (grading) return null;
  for (final o in outcomes) {
    if (o.seconds < o.turn.speakSeconds * _shortTimeRatio) {
      return _FocusFix(
        to: '시간이 끝날 때까지 이어서 말해 보세요',
        why: 'Q${o.turn.number}: ${o.seconds}초 / ${o.turn.speakSeconds}초 동안 말했어요.',
      );
    }
  }
  final said = outcomes.map((o) => o.transcript).join(' ');
  final unused = task.keyPhrases.where((p) => !usedPhrase(said, p)).toList();
  if (unused.isNotEmpty) return _FocusFix(to: '다음엔 "${unused.first}" 를 넣어 말해 보세요');
  if (task.type == ToeicTaskType.readAloud) {
    for (final o in outcomes) {
      final ref = o.turn.reference;
      if (ref == null || o.transcript.isEmpty) continue;
      final missed = scoreSpeech(ref, o.transcript).missed;
      if (missed.isNotEmpty) return _FocusFix(to: '"${missed.first}" 를 또렷하게 읽어 보세요');
    }
  }
  return null;
}

/// 다듬은 답을 문장 단위로
List<String> _sentences(String text) => [
  for (final s in text.trim().split(RegExp(r'(?<=[.!?])\s+')))
    if (s.trim().isNotEmpty) s.trim(),
];

/// ① 요약 띠: 묶음 점수 · 목표 대비 · 고칠 것 1개
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.target, required this.grading, required this.readAloud});
  final _ResultSummary summary;
  final ToeicTarget target;
  final bool grading;
  final bool readAloud;

  @override
  Widget build(BuildContext context) {
    final met = summary.targetMet;
    final fix = summary.fix;
    return Container(
      key: const ValueKey('toeic-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.colors.penBlueTint, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(summary.scoreText, style: serif(26, weight: 600)),
              if (summary.level != null) ...[
                const SizedBox(width: 10),
                _LevelBadge(level: summary.level!, met: met == true),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: met == null
                    ? Text(
                        grading
                            ? '채점하는 중'
                            : readAloud
                            ? '알아들은 단어 비율로 센 대략의 점수예요'
                            : '분량·핵심 표현으로 센 대략의 점수예요',
                        style: sans(13, color: context.colors.ink2, height: 1.4),
                      )
                    : Row(
                        children: [
                          Icon(
                            met ? Icons.check_circle_rounded : Icons.trending_up_rounded,
                            size: 18,
                            color: met ? context.colors.success : context.colors.ember,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              met ? '목표 ${target.label} 수준' : '목표 ${target.label}까지 조금 더',
                              style: sans(14, weight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (grading) ...[const SizedBox(height: 10), const LinearProgressIndicator(minHeight: 3)],
          if (fix != null) ...[
            const SizedBox(height: 12),
            Text(
              '고칠 것 1개',
              style: sans(12, weight: FontWeight.w600, color: context.colors.penBlue),
            ),
            const SizedBox(height: 4),
            _FixLine(fix: fix),
          ],
        ],
      ),
    );
  }
}

/// 고칠 말 → 고친 말 (고칠 말은 빨간색 + 취소선 + 아이콘으로, 색만으로 구분하지 않는다)
class _FixLine extends StatelessWidget {
  const _FixLine({required this.fix});
  final _FocusFix fix;

  @override
  Widget build(BuildContext context) {
    final muted = sans(13, color: context.colors.inkSoft, height: 1.5);
    final from = fix.from;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (from == null)
          Text(fix.to, style: sans(15, weight: FontWeight.w600, height: 1.45))
        else
          Semantics(
            container: true,
            label: '고칠 말: $from. 이렇게: ${fix.to}',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.close_rounded, size: 15, color: context.colors.error),
                  ),
                  TextSpan(
                    text: ' $from',
                    style: serif(16, color: context.colors.error).copyWith(decoration: TextDecoration.lineThrough),
                  ),
                  TextSpan(
                    text: '  →  ',
                    style: sans(13, color: context.colors.ink2),
                  ),
                  TextSpan(text: fix.to, style: serif(16, weight: 700)),
                ],
              ),
            ),
          ),
        if (fix.why.isNotEmpty) Text(fix.why, style: muted),
      ],
    );
  }
}

/// 등급 표시: 목표 이상이면 체크 아이콘도 붙인다 (색만으로 알리지 않는다)
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.met});
  final String level;
  final bool met;

  @override
  Widget build(BuildContext context) => Tag(
    level,
    icon: met ? Icons.check_rounded : null,
    color: met ? context.colors.success : context.colors.penBlue,
    background: context.colors.card,
  );
}

/// ② 질문 하나의 결과 카드. 머리만 보이게 접어 두고, 누르면 펼친다.
class _TurnCard extends StatelessWidget {
  const _TurnCard({
    super.key,
    required this.task,
    required this.outcome,
    required this.grade,
    required this.gradeError,
    required this.grading,
    required this.suggestions,
    required this.onPlay,
    required this.expanded,
    required this.onToggle,
  });

  final ToeicTask task;
  final TurnOutcome outcome;
  final GradeResult? grade;
  final String? gradeError;
  final bool grading;
  final List<Suggestion> suggestions;
  final void Function(String text) onPlay;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final turn = outcome.turn;
    final multi = task.turns.length > 1;
    final g = grade;
    return PaperCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: 'Q${turn.number} 자세히 ${expanded ? '접기' : '보기'}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        'Q${turn.number}',
                        style: sans(14, weight: FontWeight.w700, color: context.colors.penBlue),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          multi && turn.question != null ? turn.question! : '자세히 보기',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: multi && turn.question != null
                              ? serif(15, weight: 500)
                              : sans(13, color: context.colors.ink2),
                        ),
                      ),
                      if (grading)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      else if (multi && g != null)
                        Text('${g.score}/${g.maxScore}', style: sans(13, weight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Icon(
                        expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: context.colors.ink2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _TurnDetail(
                task: task,
                outcome: outcome,
                grade: grade,
                gradeError: gradeError,
                grading: grading,
                suggestions: suggestions,
                onPlay: onPlay,
              ),
            ),
        ],
      ),
    );
  }
}

/// 펼친 카드 내용: 들린 대로 / 분량 / 핵심 표현 / 채점 / 모범 답안
class _TurnDetail extends StatelessWidget {
  const _TurnDetail({
    required this.task,
    required this.outcome,
    required this.grade,
    required this.gradeError,
    required this.grading,
    required this.suggestions,
    required this.onPlay,
  });

  final ToeicTask task;
  final TurnOutcome outcome;
  final GradeResult? grade;
  final String? gradeError;
  final bool grading;
  final List<Suggestion> suggestions;
  final void Function(String text) onPlay;

  @override
  Widget build(BuildContext context) {
    final turn = outcome.turn;
    final said = outcome.transcript;
    final used = usedPhrases(said, task.keyPhrases).toSet();
    final usedSuggestions = [
      for (final s in suggestions)
        if (usedPhrase(said, s.check)) s.text,
    ];
    final read = task.type == ToeicTaskType.readAloud && turn.reference != null && said.isNotEmpty
        ? scoreSpeech(turn.reference!, said)
        : null;
    final muted = sans(13, color: context.colors.ink2, height: 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (turn.question != null && task.turns.length > 1) ...[
          Text(turn.question!, style: serif(16, weight: 500, height: 1.35)),
          const SizedBox(height: 10),
        ],
        // 기기 음성 인식이 알아들은 글자일 뿐, 실제 발음 그대로는 아니다
        Text(
          '들린 대로',
          style: sans(12, weight: FontWeight.w600, color: context.colors.ink2),
        ),
        const SizedBox(height: 2),
        Text(
          said.isEmpty ? '들린 말이 없어요.' : '"$said"',
          style: said.isEmpty ? muted : serif(16, italic: true, height: 1.4),
        ),
        const SizedBox(height: 8),
        Text(
          '${outcome.seconds}초 / ${turn.speakSeconds}초 동안 말함 · 단어 ${wordCount(said)}개'
          '${read != null ? ' · 알아들은 단어 ${read.score}%' : ''}',
          style: sans(13, weight: FontWeight.w600),
        ),
        if (read != null && read.missed.isNotEmpty) Text('알아듣지 못한 단어: ${read.missed.take(8).join(', ')}', style: muted),
        if (task.keyPhrases.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('핵심 표현 ${used.length}/${task.keyPhrases.length}개 사용', style: sans(12, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in task.keyPhrases)
                Tag(
                  p,
                  icon: used.contains(p) ? Icons.check_rounded : null,
                  color: used.contains(p) ? context.colors.success : context.colors.ink2,
                  background: used.contains(p) ? context.colors.successTint : context.colors.sand,
                ),
            ],
          ),
        ],
        if (usedSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('오늘 표현을 썼어요: ${usedSuggestions.join(' · ')}', style: sans(13, color: context.colors.success)),
        ],
        if (grading) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('채점 결과를 기다리는 중', style: muted),
            ],
          ),
        ] else if (grade != null) ...[
          const SizedBox(height: 12),
          _GradeCard(grade: grade!),
        ] else if (gradeError != null) ...[
          const SizedBox(height: 10),
          Text(gradeError!, style: sans(13, color: context.colors.error)),
        ],
        if (task.type != ToeicTaskType.readAloud) ...[
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '모범 답안',
                  style: sans(12, weight: FontWeight.w600, color: context.colors.ink2),
                ),
              ),
              RoundIconButton(
                icon: Icons.volume_up_rounded,
                label: 'Q${turn.number} 모범 답안 듣기',
                filled: false,
                onPressed: () => onPlay(turn.model),
              ),
            ],
          ),
          englishSemantics(turn.model, Text(turn.model, style: serif(16, height: 1.45))),
        ] else ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onPlay(turn.model),
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('원문 듣기'),
            ),
          ),
        ],
      ],
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.grade});
  final GradeResult grade;

  @override
  Widget build(BuildContext context) {
    final muted = sans(13, color: context.colors.inkSoft, height: 1.55);
    final level = toeicLevelIndex(grade.level) >= 0 ? grade.level.toUpperCase() : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.colors.sand, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('채점 ${grade.score}/${grade.maxScore}', style: sans(14, weight: FontWeight.w700)),
              if (level != null) ...[const SizedBox(width: 8), Tag(level)],
            ],
          ),
          if (grade.summaryKo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(grade.summaryKo, style: sans(14, height: 1.55)),
          ],
          for (final g in grade.goodKo) Text('· $g', style: muted),
          for (final f in grade.fixes) ...[
            const SizedBox(height: 8),
            _FixLine(
              fix: _FocusFix(from: f.from, to: f.to, why: f.whyKo),
            ),
          ],
          if (grade.improved.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '다듬은 답',
              style: sans(12, weight: FontWeight.w600, color: context.colors.penBlue),
            ),
            englishSemantics(grade.improved, Text(grade.improved, style: serif(15, height: 1.45))),
          ],
          if (grade.nextTipKo.isNotEmpty) ...[const SizedBox(height: 8), Text('다음엔: ${grade.nextTipKo}', style: muted)],
        ],
      ),
    );
  }
}

/// 따라 할 답 하나 (질문 번호, 영어 답)
typedef _ShadowAnswer = ({int number, String text});

/// ③ 다듬은 답(없으면 모범 답안·원문)을 문장 단위로: 듣기 → 바로 따라 말하기 → 알아들은 단어 비율
class _ShadowingCard extends ConsumerStatefulWidget {
  const _ShadowingCard({super.key, required this.title, required this.answers, required this.say});
  final String title;
  final List<_ShadowAnswer> answers;

  /// 원어민 읽기 (다 읽으면 끝나는 Future)
  final Future<void> Function(String text) say;

  @override
  ConsumerState<_ShadowingCard> createState() => _ShadowingCardState();
}

class _ShadowingCardState extends ConsumerState<_ShadowingCard> {
  late final SpeechInput _input;
  late final Speaker _speaker;

  /// 지금 듣고 있는 문장 번호
  int? _listening;
  final _scores = <int, int>{};
  final _errors = <int, String>{};

  @override
  void initState() {
    super.initState();
    _input = ref.read(speechInputProvider);
    _speaker = ref.read(speakerProvider);
  }

  @override
  void dispose() {
    if (_listening != null) _input.stop();
    super.dispose();
  }

  Future<void> _shadow(int i, String sentence) async {
    if (_listening == i) {
      await _input.stop();
      return;
    }
    if (_listening != null) await _input.stop();
    await _speaker.stop();
    if (!mounted) return;
    setState(() {
      _listening = i;
      _errors.remove(i);
    });
    final attempt = await _input.listen(expected: sentence);
    if (!mounted || _listening != i) return;
    setState(() {
      _listening = null;
      if (attempt.ok) {
        _scores[i] = scoreSpeech(sentence, attempt.text!).score;
      } else {
        _errors[i] = attempt.error ?? '잘 들리지 않았어요. 다시 말해 볼까요?';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.answers.length > 1;
    var i = 0;
    final rows = <Widget>[];
    for (final a in widget.answers) {
      if (multi) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              'Q${a.number}',
              style: sans(12, weight: FontWeight.w700, color: context.colors.penBlue),
            ),
          ),
        );
      }
      for (final s in _sentences(a.text)) {
        rows.add(_row(context, i++, s));
      }
    }
    return PaperCard(
      key: const ValueKey('toeic-shadowing'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: sans(15, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('한 문장씩 듣고 바로 따라 말해요.', style: sans(13, color: context.colors.ink2)),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i, String sentence) {
    final score = _scores[i];
    final error = _errors[i];
    final listening = _listening == i;
    final n = i + 1;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoundIconButton(
            icon: Icons.volume_up_rounded,
            label: '문장 $n 듣기',
            filled: false,
            size: 44,
            onPressed: () => widget.say(sentence),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                englishSemantics(sentence, Text(sentence, style: serif(16, height: 1.4))),
                if (listening)
                  Text('듣고 있어요 · 다 말하면 한 번 더 눌러요', style: sans(12, color: context.colors.penBlue))
                else if (score != null)
                  Row(
                    children: [
                      Icon(
                        score >= 80 ? Icons.check_rounded : Icons.replay_rounded,
                        size: 14,
                        color: score >= 80 ? context.colors.success : context.colors.ink2,
                      ),
                      const SizedBox(width: 4),
                      Text('알아들은 단어 $score%', style: sans(12, weight: FontWeight.w600)),
                    ],
                  )
                else if (error != null)
                  Text(error, style: sans(12, color: context.colors.error)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          RoundIconButton(
            icon: listening ? Icons.stop_rounded : Icons.mic_rounded,
            label: listening ? '문장 $n 따라 말하기 끝내기' : '문장 $n 따라 말하기',
            filled: listening,
            onPressed: () => _shadow(i, sentence),
          ),
        ],
      ),
    );
  }
}
