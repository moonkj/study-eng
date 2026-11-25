import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/routine_flow.dart' show popOrHome, toeicDailyProvider;
import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/grade_source.dart' show ToeicTaskType;
import '../../data/toeic.dart';
import '../../domain/study_log.dart';
import '../../domain/toeic_feedback.dart';
import '../../domain/toeic_weakness.dart';
import 'toeic_target.dart';
import 'toeic_task.dart';
import 'toeic_task_view.dart';

// ───────────────────────── 한 문항 연습 기록 (이번 실행 동안만) ─────────────────────────

/// 허브에서 한 문항 연습으로 말한 답 하나
class PracticeAnswer {
  const PracticeAnswer({required this.date, required this.task, required this.outcomes, required this.record});

  /// 연습한 날 (yyyy-MM-dd)
  final String date;
  final ToeicTask task;
  final List<TurnOutcome> outcomes;
  final ToeicTaskRecord record;
}

/// 한 문항 연습 기록: 앱을 켜 둔 동안만 메모리에 둔다 (저장·동기화하지 않는다).
/// 오늘 루틴 기록(`today.toeic`)과 유형별 점수(`toeicLog`)에는 넣지 않는다:
/// 같은 유형을 여러 번 연습하면 그날 가장 높은 점수만 남아 약점이 가려지기 때문이다.
class PracticeLog extends Notifier<List<PracticeAnswer>> {
  /// 최근 몇 개까지 둘지
  static const keep = 20;

  @override
  List<PracticeAnswer> build() => const [];

  void add(PracticeAnswer a) => state = [a, ...state].take(keep).toList();
}

final practiceLogProvider = NotifierProvider<PracticeLog, List<PracticeAnswer>>(PracticeLog.new);

/// 유형별 시험 문항 번호
const _typeNumbers = {
  ToeicTaskType.readAloud: 'Q1-2',
  ToeicTaskType.picture: 'Q3-4',
  ToeicTaskType.respond: 'Q5-7',
  ToeicTaskType.info: 'Q8-10',
  ToeicTaskType.opinion: 'Q11',
};

/// 문항 하나에 걸리는 대략의 시간(분): 시험 시간 + 안내·결과 보기
int practiceMinutes(ToeicTask task) => ((task.totalSeconds + 60) / 60).ceil();

// ───────────────────────── 화면 ─────────────────────────

/// 토스 허브 (집중 화면 `/toeic`): 목표 → 유형별 한 문항 연습 → 모의고사 → 내 답 모음 → 더 연습하기
class ToeicHubScreen extends ConsumerStatefulWidget {
  const ToeicHubScreen({super.key});

  @override
  ConsumerState<ToeicHubScreen> createState() => _ToeicHubScreenState();
}

class _ToeicHubScreenState extends ConsumerState<ToeicHubScreen> {
  /// 지금 하고 있는 한 문항 연습 (없으면 허브 목록)
  ToeicTask? _practice;

  /// 같은 문항을 다시 시작해도 새로 그리게
  int _run = 0;

  /// 지금 고를 수 있는 [type] 연습 문항: 오늘 루틴 문항과 이번에 연습한 문항은 피한다.
  /// (모의고사 문항까지 피하면 문항이 적은 유형은 고를 것이 남지 않아 넣지 않는다)
  ToeicTask _taskFor(ToeicBank bank, ToeicTaskType type) {
    final s = ref.read(studyProvider);
    final daily = ref.read(toeicDailyProvider);
    final avoid = <String>{
      ...s.today.toeic.keys,
      if (daily != null) ...[
        daily.readAloud.id,
        daily.picture.id,
        ?daily.respond?.id,
        ?daily.info?.id,
        ?daily.opinion?.id,
      ],
      for (final a in ref.read(practiceLogProvider)) a.task.id,
    };
    return practiceTask(bank, type, s.toeicTarget, s.now, avoid: avoid);
  }

  void _start(ToeicBank bank, ToeicTaskType type) => setState(() {
    _practice = _taskFor(bank, type);
    _run++;
  });

  void _stop() => setState(() => _practice = null);

  void _done(ToeicTask task, List<TurnOutcome> outcomes, ToeicTaskRecord record) {
    final s = ref.read(studyProvider);
    ref
        .read(practiceLogProvider.notifier)
        .add(PracticeAnswer(date: dateKey(s.now), task: task, outcomes: outcomes, record: record));
    _stop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('방금 말한 답을 내 답 모음에 담았어요')));
  }

  @override
  Widget build(BuildContext context) {
    final practice = _practice;
    return PopScope(
      // 연습 중에 뒤로 가면 허브 목록으로 돌아온다
      canPop: practice == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _practice != null) _stop();
      },
      child: Scaffold(body: SafeArea(child: practice == null ? _hub(context) : _practiceView(context, practice))),
    );
  }

  Widget _practiceView(BuildContext context, ToeicTask task) {
    final s = ref.watch(studyProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          title: '한 문항 연습 · ${toeicTypeKo[task.type]}',
          closeLabel: '연습 그만하고 토스 허브로',
          close: true,
          onClose: _stop,
        ),
        Expanded(
          child: ToeicTaskView(
            key: ValueKey('practice-${task.id}-$_run'),
            task: task,
            suggestions: [for (final e in s.pack.expressions) (text: e.pattern, check: e.highlight)],
            onComplete: (outcomes, record) => _done(task, outcomes, record),
          ),
        ),
      ],
    );
  }

  Widget _hub(BuildContext context) {
    final s = ref.watch(studyProvider);
    final bank = ref.watch(toeicBankProvider);
    final answers = ref.watch(practiceLogProvider);
    final stats = typeStats(s.toeicLog, s.mocks);
    final weak = weakestType(stats);
    final tasks = bank == null ? null : {for (final t in toeicTypeKo.keys) t: _taskFor(bank, t)};
    // 빈 '내 답 모음'에서 권할 유형: 약점, 없으면 사진 묘사
    final suggest = weak ?? ToeicTaskType.picture;
    final last = s.mocks.isEmpty ? null : s.mocks.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(title: '토스', closeLabel: '뒤로', onClose: () => popOrHome(context)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl * 2),
            children: [
              _TargetHeader(
                target: s.toeicTarget,
                chosen: s.settings.toeicTarget != null,
                lastMock: last,
                onTap: () => pickToeicTarget(context, ref),
              ),

              _SectionHeader(title: '유형별 한 문항 연습', trailing: '${s.toeicTarget.label} 목표 문항'),
              if (tasks == null)
                const _EmptyNote(icon: Icons.cloud_off_rounded, message: '문항을 불러오지 못했어요. 앱을 다시 열면 다시 불러와요.')
              else
                for (final type in toeicTypeKo.keys) ...[
                  _PracticeRow(
                    number: _typeNumbers[type]!,
                    name: toeicTypeKo[type]!,
                    stat: stats[type],
                    weak: type == weak,
                    minutes: practiceMinutes(tasks[type]!),
                    onTap: () => _start(bank!, type),
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],

              const _SectionHeader(title: '모의고사'),
              _HubRow(
                icon: Icons.timer_outlined,
                title: '실전 모의고사 · 11문항',
                subtitle: last == null
                    ? '첫 모의고사로 지금 위치를 확인해요 · 약 20분'
                    : '지난번 예상 ${last.level} · ${_dayLabel(last.date)} · 약 20분',
                onTap: bank == null ? null : () => context.push('/toeic-mock'),
              ),

              _SectionHeader(title: '내 답 모음', trailing: answers.isEmpty ? null : '${answers.length}개'),
              if (answers.isEmpty)
                _EmptyNote(
                  icon: Icons.mic_none_rounded,
                  message: '한 문항 연습을 하면 내가 말한 답과 모범 답안이 여기 모여요. 앱을 닫으면 비워져요.',
                  actionLabel: tasks == null
                      ? null
                      : '${toeicTypeKo[suggest]} 한 문항 · 약 ${practiceMinutes(tasks[suggest]!)}분',
                  onAction: tasks == null ? null : () => _start(bank!, suggest),
                )
              else
                PaperCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
                  // 펼치는 줄(ListTile)이 카드 배경 위에 그려지게
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(children: [for (final a in answers) _AnswerTile(answer: a)]),
                  ),
                ),

              const _SectionHeader(title: '더 연습하기'),
              _HubRow(
                icon: Icons.edit_note_rounded,
                title: '내 상황으로 말하기',
                subtitle: '오늘 표현으로 내 이야기 한 문장 · 약 3분',
                onTap: () => context.push('/my-sentence'),
              ),
              const SizedBox(height: AppSpace.sm),
              _HubRow(
                icon: Icons.forum_outlined,
                title: '대화 듣기',
                subtitle: '오늘 표현이 쓰인 대화 · 약 3분',
                onTap: () => context.push('/dialogue'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _dayLabel(String key) {
  final d = parseDateKey(key);
  return '${d.month}월 ${d.day}일';
}

// ───────────────────────── 화면 조각 ─────────────────────────
// 아래 위젯들은 이 화면 전용이다. 공통 컴포넌트(core/widgets 의 SectionHeader·ActionRow·EmptyState 등)가
// 들어오면 같은 인자로 바꿔 끼울 수 있게 모양을 맞춰 두었다.

/// 위 막대: 닫기(뒤로) + 제목
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.closeLabel, required this.onClose, this.close = false});
  final String title;
  final String closeLabel;
  final VoidCallback onClose;
  final bool close;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.md, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: closeLabel,
            onPressed: onClose,
            icon: Icon(close ? Icons.close_rounded : Icons.chevron_left_rounded, size: 26),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: sans(17, weight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 목표 머리: 목표 등급·점수 + 지난 모의고사 예상 등급. 누르면 목표 바꾸기 시트.
class _TargetHeader extends StatelessWidget {
  const _TargetHeader({required this.target, required this.chosen, required this.lastMock, required this.onTap});
  final ToeicTarget target;

  /// 직접 고른 목표인지 (아니면 기본 목표)
  final bool chosen;
  final MockResult? lastMock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = lastMock;
    final met = m != null && meetsTarget(m.level, target);
    final estimate = m == null ? '모의고사를 보면 예상 등급이 나와요' : '지난 모의고사 예상 ${m.level}';
    return Semantics(
      button: true,
      label: '목표 ${target.label}, ${target.score}점${chosen ? '' : ', 기본 목표'}. $estimate${met ? ', 목표 달성' : ''}. 목표 바꾸기',
      excludeSemantics: true,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chosen ? '나의 토스 목표' : '토스 목표 (기본)',
                        style: sans(12, weight: FontWeight.w600, color: c.ink2),
                      ),
                    ),
                    Text(
                      '바꾸기',
                      style: sans(13, weight: FontWeight.w600, color: c.penBlue),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: c.penBlue),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: AppSpace.sm,
                  children: [
                    Text(target.label, style: serif(30, weight: 500, letterSpacing: -0.3)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('${target.score}점 · 공식 구간 ${target.range}', style: sans(14, color: c.ink2)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(estimate, style: sans(14, weight: m == null ? FontWeight.w400 : FontWeight.w600)),
                    if (met) Tag('목표 달성', icon: Icons.check_rounded, color: c.success, background: c.successTint),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 묶음 제목 (오른쪽에 짧은 설명)
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxl + AppSpace.sm, bottom: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: sans(17, weight: FontWeight.w600)),
            ),
          ),
          if (trailing != null) Text(trailing!, style: sans(12, color: context.colors.ink2)),
        ],
      ),
    );
  }
}

/// 누르면 어딘가로 가는 한 줄 (아이콘 · 제목 · 부제 · 화살표)
class _HubRow extends StatelessWidget {
  const _HubRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: '$title, $subtitle',
      onTap: onTap,
      leading: Icon(icon, color: context.colors.penBlue, size: 22),
      title: Text(title, style: sans(15, weight: FontWeight.w600)),
      subtitle: Text(subtitle, style: sans(12, color: context.colors.ink2)),
      trailing: Icon(Icons.chevron_right_rounded, color: context.colors.ink2, size: 20),
    );
  }
}

/// 유형 한 줄: 문항 번호 · 유형 이름 · 최근 점수 · 약점 표시 · 걸리는 시간 → 누르면 한 문항 연습
class _PracticeRow extends StatelessWidget {
  const _PracticeRow({
    required this.number,
    required this.name,
    required this.stat,
    required this.weak,
    required this.minutes,
    required this.onTap,
  });
  final String number;
  final String name;
  final TypeStat? stat;
  final bool weak;
  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avg = stat?.average.round();
    final score = avg == null ? '아직 기록 없음' : '최근 평균 $avg점';
    return _RowShell(
      label: '$name 한 문항 연습, $number, $score${weak ? ', 약점' : ''}, 약 $minutes분',
      onTap: onTap,
      emphasis: weak,
      leading: SizedBox(
        width: 48,
        child: Text(
          number,
          style: sans(12, weight: FontWeight.w700, color: c.ink2),
        ),
      ),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.sm,
        runSpacing: AppSpace.xs,
        children: [
          Text(name, style: sans(15, weight: FontWeight.w600)),
          // 색만으로 약점을 알리지 않게 글자 태그로
          if (weak) Tag('약점', icon: Icons.priority_high_rounded, color: c.error, background: c.errorTint),
        ],
      ),
      subtitle: Text('$score · 약 $minutes분', style: sans(12, color: c.ink2)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '연습',
            style: sans(13, weight: FontWeight.w600, color: c.penBlue),
          ),
          Icon(Icons.chevron_right_rounded, color: c.penBlue, size: 20),
        ],
      ),
    );
  }
}

/// 한 줄의 공통 틀: 최소 높이 60, 전체가 버튼 하나로 읽힌다
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.label,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.emphasis = false,
  });
  final String label;
  final VoidCallback? onTap;
  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final Widget trailing;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            side: BorderSide(color: emphasis ? c.lineStrong : c.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 2), subtitle],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    trailing,
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

/// 빈 상태: 아이콘 + 한 줄 + (있으면) 다음 행동 버튼(걸리는 시간 포함)
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PaperCard(
      color: c.sand,
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, color: c.ink2, size: 22)),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text(message, style: sans(14, height: 1.5))),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 내 답 하나: 펼치면 질문 · 내 답 · 모범 답안(듣기)
class _AnswerTile extends ConsumerWidget {
  const _AnswerTile({required this.answer});
  final PracticeAnswer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final r = answer.record;
    final first = answer.outcomes.isEmpty ? '' : answer.outcomes.first.transcript;
    final say = ref.read(sayProvider);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpace.md),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(answer.task.title, style: sans(14, weight: FontWeight.w600)),
      subtitle: Text(
        first.isEmpty ? '들린 말이 없어요' : first,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: serif(14, italic: true, color: c.ink2),
      ),
      trailing: Text(
        r.graded ? '${r.score}점' : '대략 ${r.score}점',
        style: sans(13, weight: FontWeight.w600),
        semanticsLabel: r.graded ? '채점 ${r.score}점' : '기기에서 계산한 대략 ${r.score}점',
      ),
      children: [
        for (final o in answer.outcomes) ...[
          if (o.turn.question != null) ...[
            Text(
              'Q${o.turn.number}',
              style: sans(12, weight: FontWeight.w600, color: c.ink2),
            ),
            englishSemantics(o.turn.question!, Text(o.turn.question!, style: serif(15, weight: 500, height: 1.4))),
            const SizedBox(height: AppSpace.xs),
          ],
          Text(
            '내 답',
            style: sans(12, weight: FontWeight.w600, color: c.ink2),
          ),
          if (o.transcript.isEmpty)
            Text('들린 말이 없어요.', style: sans(14, color: c.ink2))
          else
            englishSemantics(o.transcript, Text(o.transcript, style: serif(15, italic: true, height: 1.4))),
          Row(
            children: [
              Expanded(
                child: Text(
                  '모범 답안',
                  style: sans(12, weight: FontWeight.w600, color: c.ink2),
                ),
              ),
              IconButton(
                tooltip: 'Q${o.turn.number} 모범 답안 듣기',
                icon: const Icon(Icons.volume_up_rounded),
                onPressed: () => say(o.turn.model),
              ),
            ],
          ),
          englishSemantics(o.turn.model, Text(o.turn.model, style: serif(15, height: 1.45))),
          const SizedBox(height: AppSpace.md),
        ],
      ],
    );
  }
}
