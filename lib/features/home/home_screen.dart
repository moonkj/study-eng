import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routine_flow.dart';
import '../../app/study_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/grade_source.dart' show ToeicTaskType;
import '../../data/models.dart' show Expression;
import '../../domain/study_log.dart';
import '../../domain/toeic_level.dart';
import '../../domain/toeic_weakness.dart';
import '../../data/toeic.dart';
import '../commute/commute_home.dart';
import '../toeic/toeic_target.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String koreanDate(DateTime d) => '${d.month}월 ${d.day}일 ${_weekdays[d.weekday - 1]}요일';

String greeting(DateTime d) => switch (d.hour) {
  < 5 => '늦은 밤이에요',
  < 12 => '좋은 아침이에요',
  < 18 => '좋은 오후예요',
  _ => '오늘 하루 수고했어요',
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final toeic = ref.watch(toeicDailyProvider);
    final bank = ref.watch(toeicBankProvider);
    final now = ref.watch(clockProvider)();
    // 학습일 새로 고침은 app.dart 의 라우터 리스너가 탭 화면에 있을 때만 한다
    // (홈은 학습 화면 뒤에서도 다시 그려지므로 여기서 하면 루틴 도중 진행이 지워진다)
    // 내용 영역 폭 기준 (iPad 에서는 내비게이션 폭을 뺀 값): 두 단이 답답하지 않을 때만 나눈다
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final estimate = s.toeicEstimate;
    final stats = typeStats(s.toeicLog, s.mocks);

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(koreanDate(s.now), style: AppType.callout(color: context.colors.ink2, letterSpacing: 0.2)),
              const SizedBox(height: AppSpace.xs),
              Text(greeting(now), style: AppType.title1(weight: FontWeight.w700, letterSpacing: -0.5)),
              if (!s.allDone && s.restsUsedRecently > 0) ...[
                const SizedBox(height: AppSpace.xs),
                Text('쉬는 날 ${s.restsUsedRecently}개로 연속 기록을 지켰어요', style: AppType.callout(color: context.colors.ink2)),
              ],
            ],
          ),
        ),
        _StreakChip(
          days: s.streakDays,
          longest: s.longestStreak,
          doneToday: s.allDone,
          // 쉬는 날이 남아 있으면 저녁이라도 겁주지 않는다
          evening: now.hour >= 18 && s.streak.restsLeft == 0,
        ),
      ],
    );

    // 맨 위 히어로: 토스 목표까지의 거리 (탭하면 토스 화면)
    final goalCard = _GoalCard(
      target: s.toeicTarget,
      estimate: estimate,
      stats: stats,
      weak: weakestType(stats),
      onTap: () => context.push('/toeic'),
    );

    // 알림은 목표 카드 위에 하나만: 목표 달성 > 이어서 하기 > 기본 팩 안내
    final carriedFrom = s.today.carriedFrom;
    final Widget? notice = s.targetReached
        ? const TargetReachedCard()
        : carriedFrom != null && !s.allDone
        ? Builder(
            builder: (context) {
              final days = daysBetween(parseDateKey(carriedFrom), s.now);
              return AppBanner(
                icon: Icons.redo_rounded,
                message: '${days <= 1 ? '어제' : '$days일 전에'} 하던 루틴을 이어서 해요. 한 만큼은 기록에 남았어요.',
                actions: [
                  TextButton(onPressed: ref.read(studyProvider.notifier).dropCarried, child: const Text('새로 시작')),
                ],
              );
            },
          )
        : s.packError != null && s.untouched
        ? AppBanner(
            icon: Icons.cloud_off_rounded,
            message: '${s.packError!} 오늘은 기본 학습으로 진행할 수 있어요.',
            actions: [
              TextButton(onPressed: () => ref.read(studyProvider.notifier).loadTodayPack(), child: const Text('다시 시도')),
            ],
          )
        : null;

    // 주 버튼 하나: 다음에 할 단계로 바로 (단계 끝의 '이어서 하기' 시트는 각 화면에 그대로 있다).
    // 루틴을 다 끝낸 날은 버튼 대신 완료 배너(복습 카드가 있으면 그 안에 복습 버튼)
    final Widget primary = s.allDone
        ? _DoneCard(state: s)
        : _PrimaryButton(state: s, toeic: toeic, onPressed: () => context.push(routinePaths[s.current]!));

    final routine = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '오늘의 루틴',
          trailing: s.allDone
              ? '4/4 완료'
              : (s.log[dateKey(s.now)]?.mini ?? false)
              ? '3분 루틴으로 오늘 기록 완료 · 남은 단계도 할 수 있어요'
              : '남은 시간 약 ${remainingMinutes(s, toeic: toeic)}분 · ${s.done.length}/4',
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
        ),
        for (final step in RoutineStep.values) ...[
          _RoutineRow(step: step, state: s, toeic: toeic),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );

    // 루틴 아래 바로 갈 곳: 복습 · 모의고사 · 출퇴근
    final more = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!wide && s.dueCount > 0) ...[
          _ReviewRow(count: s.dueCount, minutes: s.reviewMinutes),
          const SizedBox(height: AppSpace.sm),
        ],
        if (bank != null) ...[
          MockEntryCard(
            // 주말에는 모의고사를 권한다 (언제든 볼 수 있다)
            weekend: s.now.weekday >= DateTime.saturday,
            last: s.mocks.isEmpty ? null : s.mocks.last.estimate?.label,
            onTap: () => context.push('/toeic-mock'),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        const CommuteEntry(),
      ],
    );

    final expression = s.packLoading ? null : _ExpressionCard(expression: s.pack.expressions.first);

    // iPad 가로: 왼쪽(목표 · 주 버튼 · 루틴) / 오른쪽(복습 · 모의고사 · 오늘의 표현)
    if (wide) {
      return SafeArea(
        child: ListView(
          padding: readablePadding(context, maxWidth: 1040, top: 28),
          children: [
            header,
            const SizedBox(height: AppSpace.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (notice != null) ...[notice, const SizedBox(height: AppSpace.md)],
                      goalCard,
                      const SizedBox(height: AppSpace.lg),
                      if (s.packLoading)
                        _PreparingCard(onSkip: ref.read(studyProvider.notifier).startWithFallback)
                      else ...[
                        primary,
                        const SizedBox(height: AppSpace.xxl),
                        routine,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.xxl),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReviewSummary(state: s),
                      const SizedBox(height: AppSpace.md),
                      more,
                      if (expression != null) ...[const SizedBox(height: AppSpace.md), expression],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: readablePadding(context, maxWidth: 680),
        children: [
          header,
          const SizedBox(height: AppSpace.lg),
          if (notice != null) ...[notice, const SizedBox(height: AppSpace.md)],
          goalCard,
          const SizedBox(height: AppSpace.lg),
          if (s.packLoading)
            _PreparingCard(onSkip: ref.read(studyProvider.notifier).startWithFallback)
          else ...[
            primary,
            const SizedBox(height: AppSpace.xxl),
            routine,
            more,
            const SizedBox(height: AppSpace.lg),
            ?expression,
          ],
        ],
      ),
    );
  }
}

/// 맨 위 '오늘의 목표' 카드: 목표 · 지금 예상 등급 · 등급 눈금(공통 LevelScale) · 유형별 미니 막대 · (시험일)
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.target,
    required this.estimate,
    required this.stats,
    required this.onTap,
    this.weak,
    // ignore: unused_element_parameter
    this.examDate,
    // ignore: unused_element_parameter
    this.today,
  });

  final ToeicTarget target;
  final ToeicEstimate estimate;
  final Map<ToeicTaskType, TypeStat> stats;
  final ToeicTaskType? weak;
  final VoidCallback onTap;

  /// 시험일 (아직 입력하는 곳이 없어 늘 null → 숨김. 시험일 기능(P1-10)이 생기면 넘긴다)
  final DateTime? examDate;
  final DateTime? today;

  static const _short = {
    ToeicTaskType.readAloud: '문장 읽기',
    ToeicTaskType.picture: '사진',
    ToeicTaskType.respond: '질문',
    ToeicTaskType.info: '표',
    ToeicTaskType.opinion: '의견',
  };

  int? get _daysLeft => examDate == null || today == null
      ? null
      : DateTime(
          examDate!.year,
          examDate!.month,
          examDate!.day,
        ).difference(DateTime(today!.year, today!.month, today!.day)).inDays;

  @override
  Widget build(BuildContext context) {
    final days = _daysLeft;
    final now = estimate.approximate ? '예상 ${estimate.label}' : '지금 ${estimate.label}';
    // 스크린리더: 한 문장 요약
    final summary = [
      '오늘의 목표',
      '목표 ${toeicLevelLabel(target.label)}',
      estimate.approximate
          ? '예상 ${estimate.low}'
          : '지금 예상 ${estimate.low}${estimate.isRange ? '에서 ${estimate.high}' : ''}',
      if (weak != null) '약점 ${toeicTypeKo[weak]}',
      if (days != null && days >= 0) '시험까지 $days일',
    ].join(', ');
    return Semantics(
      button: true,
      label: summary,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          boxShadow: AppShadow.card(context.colors),
        ),
        child: Material(
          color: context.colors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.hero),
            side: BorderSide(color: context.colors.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.hero),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '오늘의 목표',
                        style: AppType.caption(
                          weight: FontWeight.w600,
                          color: context.colors.penBlue,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const Spacer(),
                      if (days != null && days >= 0)
                        Text(
                          days == 0 ? '오늘 시험' : '시험까지 $days일',
                          // 7일 안이면 눈에 띄게 (크게 키우지는 않는다)
                          style: AppType.caption(
                            weight: FontWeight.w600,
                            color: days <= 7 ? context.colors.ember : context.colors.ink2,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text('목표 ${toeicLevelLabel(target.label)}', style: AppType.headline(weight: FontWeight.w600)),
                  const SizedBox(height: AppSpace.xs),
                  Text(now, style: AppType.enTitle(weight: 500, color: context.colors.penBlue)),
                  const SizedBox(height: AppSpace.xs),
                  Text(estimate.basis, style: AppType.caption(color: context.colors.ink2, height: 1.4)),
                  const SizedBox(height: AppSpace.md),
                  LevelScale(
                    current: estimate.low,
                    currentHigh: estimate.high,
                    target: target.label,
                    previous: estimate.previous,
                  ),
                  const SizedBox(height: AppSpace.md),
                  if (stats.isEmpty)
                    Text('토스 말하기를 하면 유형별 점수가 쌓여요 · 하루 약 8분', style: AppType.caption(color: context.colors.ink2))
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in _short.keys) ...[
                          if (t != _short.keys.first) const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: _TypeMiniBar(name: _short[t]!, average: stats[t]?.average, weak: t == weak),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: AppSpace.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '토스 전체 보기',
                          style: AppType.callout(weight: FontWeight.w600, color: context.colors.penBlue),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: context.colors.penBlue),
                      ],
                    ),
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

/// 목표 카드 안 유형 하나의 미니 막대 (약점은 색만이 아니라 글자로도)
class _TypeMiniBar extends StatelessWidget {
  const _TypeMiniBar({required this.name, required this.average, required this.weak});
  final String name;
  final double? average;
  final bool weak;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.micro(weight: weak ? FontWeight.w700 : FontWeight.w400, color: context.colors.ink2),
        ),
        const SizedBox(height: AppSpace.xs),
        ThinProgress((average ?? 0) / 100, height: 6, color: weak ? context.colors.ember : context.colors.penBlue),
        if (weak) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            '약점',
            style: AppType.micro(weight: FontWeight.w700, color: context.colors.error),
          ),
        ],
      ],
    );
  }
}

/// 홈의 주 버튼: 시작 전 "오늘 루틴 시작 · 약 N분" / 진행 중 "다음: ○○ 이어서 · 약 N분"
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.state, required this.toeic, required this.onPressed});
  final StudyState state;
  final ToeicDailySet? toeic;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final minutes = remainingMinutes(state, toeic: toeic);
    final label = state.untouched
        ? '오늘 루틴 시작 · 약 $minutes분'
        : '다음: ${stepTitle(state.current!, state, toeic: toeic)} 이어서 · 약 $minutes분';
    return FilledButton(
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// 맨 아래 작은 카드: 오늘의 표현 (형광펜은 그대로)
class _ExpressionCard extends ConsumerWidget {
  const _ExpressionCard({required this.expression});
  final Expression expression;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exp = expression;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '오늘의 표현',
                  style: AppType.caption(weight: FontWeight.w600, color: context.colors.penBlue),
                ),
                const SizedBox(height: AppSpace.sm),
                HighlightText(exp.pattern, highlight: exp.highlight, style: AppType.enBody(weight: 500, height: 1.25)),
                const SizedBox(height: AppSpace.xs),
                Text(exp.meaning, style: AppType.callout(color: context.colors.ink2)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          RoundIconButton(
            icon: Icons.volume_up_rounded,
            label: '예문 듣기',
            filled: false,
            onPressed: () => ref.read(sayProvider)(exp.examples.first.en),
          ),
        ],
      ),
    );
  }
}

/// iPad 가로 화면 오른쪽: 오늘 복습할 카드와 최근 조정 내역
class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final due = state.dueCount;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('복습', style: AppType.callout(weight: FontWeight.w600)),
          const SizedBox(height: AppSpace.sm),
          Text('$due장', style: AppType.enHero(weight: 500)),
          Text('오늘 다시 볼 카드', style: AppType.caption(color: context.colors.ink2)),
          if (state.lastAdjustmentReasons.isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            const Divider(),
            const SizedBox(height: AppSpace.md),
            Text('최근 자동 조정', style: AppType.callout(weight: FontWeight.w600)),
            const SizedBox(height: AppSpace.sm),
            for (final r in state.lastAdjustmentReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Text('· $r', style: AppType.callout(color: context.colors.ink2, height: 1.5)),
              ),
          ],
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: due > 0
                ? FilledButton(
                    onPressed: () => context.push('/review-session'),
                    child: Text('복습 카드 $due장 넘기기 · ${state.reviewMinutes}분'),
                  )
                : TextButton(onPressed: () => context.go('/review'), child: const Text('복습 탭으로')),
          ),
        ],
      ),
    );
  }
}

/// Claude 가 오늘의 맞춤 팩을 만드는 동안. 기다리지 않고 기본 학습으로 시작할 수도 있다.
class _PreparingCard extends StatefulWidget {
  const _PreparingCard({required this.onSkip});
  final VoidCallback onSkip;

  @override
  State<_PreparingCard> createState() => _PreparingCardState();
}

class _PreparingCardState extends State<_PreparingCard> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    // 20초가 넘으면 '바로 시작'을 주 버튼으로 올린다
    _timer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      elevated: true,
      radius: AppRadius.hero,
      padding: const EdgeInsets.fromLTRB(AppSpace.xxl, AppSpace.xxl, AppSpace.xxl, AppSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘의 학습',
            style: AppType.caption(weight: FontWeight.w600, color: context.colors.penBlue),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('목표에 맞춰\n오늘의 학습을 만들고 있어요', style: AppType.title2(weight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: AppSpace.sm),
          Text(
            _slow ? '조금 오래 걸리고 있어요. 기본 학습으로 먼저 시작해도 돼요.' : '오늘의 표현·단어와 퀴즈를 만들고 있어요 · 보통 30초~1분',
            style: AppType.caption(color: context.colors.ink2),
          ),
          const SizedBox(height: AppSpace.lg),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(
              minHeight: 4,
              color: context.colors.highlighter,
              backgroundColor: context.colors.track,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          if (_slow)
            FilledButton(onPressed: widget.onSkip, child: const Text('기본 학습으로 바로 시작'))
          else
            TextButton(onPressed: widget.onSkip, child: const Text('기다리지 않고 기본 학습으로 시작')),
        ],
      ),
    );
  }
}

/// 오늘 루틴을 다 끝낸 날의 홈
class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.md, AppSpace.lg),
      decoration: BoxDecoration(color: context.colors.emphasis, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_rounded, color: context.colors.onEmphasisAccent),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '오늘 루틴 완료 · ${state.streakDays}일째',
                  style: AppType.body(weight: FontWeight.w700, color: context.colors.onEmphasis),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  state.dueCount > 0
                      ? '복습 카드 ${state.dueCount}장이 기다려요. ${state.reviewMinutes}분이면 돼요.'
                      : '오늘 복습까지 끝! 내일 만나요.',
                  style: AppType.callout(color: context.colors.onEmphasisSoft),
                ),
              ],
            ),
          ),
          if (state.dueCount > 0)
            TextButton(
              onPressed: () => context.push('/review-session'),
              style: TextButton.styleFrom(foregroundColor: context.colors.onEmphasisAccent),
              child: const Text('복습하기'),
            ),
        ],
      ),
    );
  }
}

/// 루틴 아래: 오늘 복습할 카드가 있으면 바로 넘길 수 있게
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.count, required this.minutes});
  final int count;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return ActionRow(
      icon: Icons.replay_rounded,
      title: '복습 카드 $count장',
      value: '$minutes분',
      onTap: () => context.push('/review-session'),
    );
  }
}

/// 연속 학습일 칩: 오늘 했는지, 오늘 안 하면 끊기는지를 한눈에
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days, required this.longest, required this.doneToday, required this.evening});
  final int days;
  final int longest;
  final bool doneToday;
  final bool evening;

  @override
  Widget build(BuildContext context) {
    final atRisk = !doneToday && days > 0 && evening;
    final label = doneToday
        ? '$days일째'
        : days == 0
        ? (longest > 0 ? '다시 시작 · 최고 $longest일' : '오늘부터 시작')
        : '오늘 하면 ${days + 1}일';
    return Semantics(
      label: doneToday
          ? '연속 $days일, 오늘 완료'
          : (days == 0 ? (longest > 0 ? '다시 시작, 최고 기록 $longest일' : '오늘부터 시작') : '연속 $days일, 오늘 하면 ${days + 1}일'),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: atRisk ? context.colors.ember : (doneToday ? context.colors.emphasis : context.colors.card),
          borderRadius: BorderRadius.circular(AppRadius.row),
          border: Border.all(
            color: atRisk ? context.colors.ember : (doneToday ? context.colors.emphasis : context.colors.line),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              doneToday ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
              size: 16,
              color: atRisk
                  ? context.colors.card
                  : (doneToday ? context.colors.onEmphasisAccent : context.colors.ember),
            ),
            const SizedBox(width: AppSpace.xs),
            Text(
              label,
              style: AppType.callout(
                weight: FontWeight.w600,
                color: atRisk || doneToday ? context.colors.onEmphasis : context.colors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.step, required this.state, this.toeic});
  final RoutineStep step;
  final StudyState state;
  final ToeicDailySet? toeic;

  static const _blockKo = {ToeicBlock.respond: '질문 답하기', ToeicBlock.info: '표 보고 답하기', ToeicBlock.opinion: '의견 말하기'};

  (String, String) get _texts => switch (step) {
    RoutineStep.expressions => (stepTitle(step, state), '${stepMinutes(step, state)}분'),
    RoutineStep.words => (stepTitle(step, state), '${stepMinutes(step, state)}분'),
    RoutineStep.speaking => (
      stepTitle(step, state, toeic: toeic),
      toeic != null
          ? '문장 읽기 · 사진 묘사 · ${_blockKo[toeic!.block]}${toeic!.focused ? '(약점)' : ''} · ${stepMinutes(step, state, toeic: toeic)}분'
          : '${state.pack.sentences.length}문장 · ${stepMinutes(step, state)}분',
    ),
    RoutineStep.quiz => (
      stepTitle(step, state),
      state.pack.reviewCount == 0
          ? '${state.pack.quiz.length}문항 · ${stepMinutes(step, state)}분'
          : '오늘 ${state.pack.quiz.length - state.pack.reviewCount}문항 + 지난 복습 ${state.pack.reviewCount}문항',
    ),
  };

  double get _progress => switch (step) {
    RoutineStep.words => state.wordRatings.length / state.pack.words.length,
    RoutineStep.speaking =>
      toeic != null ? state.today.toeic.length / 3 : state.spokenCount / state.pack.sentences.length,
    RoutineStep.quiz => state.quizAnswers.length / state.pack.quiz.length,
    RoutineStep.expressions => state.expressionKnown.length / state.pack.expressions.length,
  };

  @override
  Widget build(BuildContext context) {
    final done = state.done.contains(step);
    final current = state.current == step;
    final (title, sub) = _texts;
    // 루틴 행은 진행 표시: 주 버튼이 '다음 할 것'을 맡으므로 지금 단계는 테두리·진행 막대로만 구분한다
    return ActionRow(
      number: step.index + 1,
      title: title,
      subtitle: sub,
      state: done
          ? ActionRowState.done
          : current
          ? ActionRowState.current
          : ActionRowState.normal,
      progress: current ? _progress : null,
      value: current ? '지금' : null,
      onTap: () => context.push(routinePaths[step]!),
    );
  }
}
