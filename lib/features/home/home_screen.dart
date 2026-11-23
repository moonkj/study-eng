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
    final now = ref.watch(clockProvider)();
    // 학습일 새로 고침은 app.dart 의 라우터 리스너가 탭 화면에 있을 때만 한다
    // (홈은 학습 화면 뒤에서도 다시 그려지므로 여기서 하면 루틴 도중 진행이 지워진다)
    final exp = s.pack.expressions.first;
    // 내용 영역 폭 기준 (iPad 에서는 내비게이션 폭을 뺀 값): 두 단이 답답하지 않을 때만 나눈다
    final wide = MediaQuery.sizeOf(context).width >= 760;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(koreanDate(s.now), style: sans(13, color: context.colors.ink2, letterSpacing: 0.2)),
              const SizedBox(height: 4),
              Text(greeting(now), style: sans(26, weight: FontWeight.w700, letterSpacing: -0.5)),
              if (!s.allDone && s.restsUsedRecently > 0) ...[
                const SizedBox(height: 4),
                Text('쉬는 날 ${s.restsUsedRecently}개로 연속 기록을 지켰어요', style: sans(13, color: context.colors.ink2)),
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

    final heroCard = PaperCard(
      elevated: true,
      radius: AppRadius.hero,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "TODAY'S EXPRESSION",
                style: sans(12, weight: FontWeight.w600, color: context.colors.penBlue, letterSpacing: 1),
              ),
              const Spacer(),
              Text('1 / ${s.pack.expressions.length}', style: sans(12, color: context.colors.ink2)),
            ],
          ),
          const SizedBox(height: 14),
          HighlightText(
            exp.pattern,
            highlight: exp.highlight,
            style: serif(30, weight: 500, height: 1.15, letterSpacing: -0.3),
          ),
          const SizedBox(height: 6),
          Text(exp.meaning, style: sans(15, color: context.colors.ink2)),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: englishSemantics(
                  exp.examples.first.en,
                  Text('"${exp.examples.first.en}"', style: serif(15, italic: true, color: context.colors.inkSoft)),
                ),
              ),
              RoundIconButton(
                icon: Icons.volume_up_rounded,
                label: '예문 듣기',
                onPressed: () => ref.read(sayProvider)(exp.examples.first.en),
              ),
            ],
          ),
        ],
      ),
    );

    final routine = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('오늘의 루틴', style: sans(17, weight: FontWeight.w700)),
            const Spacer(),
            Text(
              s.allDone ? '4/4 완료' : '남은 시간 약 ${remainingMinutes(s)}분 · ${s.done.length}/4',
              style: sans(13, color: context.colors.ink2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final step in RoutineStep.values) ...[_RoutineRow(step: step, state: s), const SizedBox(height: 8)],
      ],
    );

    final notice = s.packError != null && s.untouched
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FallbackNotice(
              message: s.packError!,
              onRetry: () => ref.read(studyProvider.notifier).loadTodayPack(),
            ),
          )
        : null;

    // iPad 가로: 왼쪽(오늘의 표현 + 루틴) / 오른쪽(레벨 · 복습 요약)
    if (wide) {
      return SafeArea(
        child: ListView(
          padding: readablePadding(context, maxWidth: 1040, top: 28),
          children: [
            header,
            const SizedBox(height: 20),
            if (s.packLoading)
              _PreparingCard(onSkip: ref.read(studyProvider.notifier).startWithFallback)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ?notice,
                        if (s.allDone) ...[_DoneCard(state: s), const SizedBox(height: 16)],
                        heroCard,
                        const SizedBox(height: 24),
                        routine,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LevelStrip(state: s),
                        const SizedBox(height: 12),
                        _ReviewSummary(state: s),
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
          if (s.packLoading) ...[
            _PreparingCard(onSkip: ref.read(studyProvider.notifier).startWithFallback),
            const SizedBox(height: 22),
            _LevelStrip(state: s),
          ] else ...[
            ?notice,
            if (s.allDone) ...[_DoneCard(state: s), const SizedBox(height: 16)],
            heroCard,
            const SizedBox(height: 22),
            routine,
            if (s.dueCount > 0) ...[_ReviewRow(count: s.dueCount, minutes: s.reviewMinutes), const SizedBox(height: 8)],
            const SizedBox(height: 6),
            _LevelStrip(state: s),
          ],
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
          Text('복습', style: sans(14, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('$due장', style: serif(32, weight: 500)),
          Text('오늘 다시 볼 카드', style: sans(13, color: context.colors.ink2)),
          if (state.lastAdjustmentReasons.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text('최근 자동 조정', style: sans(13, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final r in state.lastAdjustmentReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $r', style: sans(13, color: context.colors.ink2, height: 1.5)),
              ),
          ],
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S PACK",
            style: sans(12, weight: FontWeight.w600, color: context.colors.penBlue, letterSpacing: 1),
          ),
          const SizedBox(height: 14),
          Text('내 레벨에 맞춰\n오늘의 학습을 만들고 있어요', style: sans(20, weight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          Text(
            _slow ? '조금 오래 걸리고 있어요. 기본 학습으로 먼저 시작해도 돼요.' : '표현 3개, 단어 10개, 문장과 퀴즈까지 · 보통 30초~1분',
            style: sans(13, color: context.colors.ink2),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            child: LinearProgressIndicator(
              minHeight: 4,
              color: context.colors.highlighter,
              backgroundColor: context.colors.track,
            ),
          ),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(color: context.colors.emphasis, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_rounded, color: context.colors.onEmphasisAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '오늘 루틴 완료 · ${state.streakDays}일째',
                  style: sans(15, weight: FontWeight.w700, color: context.colors.onEmphasis),
                ),
                const SizedBox(height: 2),
                Text(
                  state.dueCount > 0
                      ? '복습 카드 ${state.dueCount}장이 기다려요. ${state.reviewMinutes}분이면 돼요.'
                      : '오늘 복습까지 끝! 내일 만나요.',
                  style: sans(13, color: context.colors.onEmphasisSoft),
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
    return Material(
      color: context.colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/review-session'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.replay_rounded, color: context.colors.penBlue, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('복습 카드 $count장', style: sans(15, weight: FontWeight.w500)),
                ),
                Text('$minutes분', style: sans(13, color: context.colors.ink2)),
                Icon(Icons.chevron_right_rounded, color: context.colors.ink2, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 맞춤 팩을 못 받아 기본 팩으로 진행할 때
class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(color: context.colors.sand, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: context.colors.ink2),
          const SizedBox(width: 10),
          Expanded(child: Text('$message 오늘은 기본 학습으로 진행할 수 있어요.', style: sans(13, height: 1.45))),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: atRisk ? context.colors.ember : (doneToday ? context.colors.emphasis : context.colors.card),
          borderRadius: BorderRadius.circular(16),
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
            const SizedBox(width: 4),
            Text(
              label,
              style: sans(
                13,
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
  const _RoutineRow({required this.step, required this.state});
  final RoutineStep step;
  final StudyState state;

  (String, String) get _texts => switch (step) {
    RoutineStep.expressions => (stepTitle(step, state), '${stepMinutes(step)}분'),
    RoutineStep.words => (stepTitle(step, state), '${stepMinutes(step)}분'),
    RoutineStep.speaking => (stepTitle(step, state), '${state.pack.sentences.length}문장 · ${stepMinutes(step)}분'),
    RoutineStep.quiz => (
      stepTitle(step, state),
      state.pack.reviewCount == 0
          ? '${state.pack.quiz.length}문항 · ${stepMinutes(step)}분'
          : '오늘 ${state.pack.quiz.length - state.pack.reviewCount}문항 + 지난 복습 ${state.pack.reviewCount}문항',
    ),
  };

  double get _progress => switch (step) {
    RoutineStep.words => state.wordRatings.length / state.pack.words.length,
    RoutineStep.speaking => state.spokenCount / state.pack.sentences.length,
    RoutineStep.quiz => state.quizAnswers.length / state.pack.quiz.length,
    RoutineStep.expressions => state.expressionKnown.length / state.pack.expressions.length,
  };

  @override
  Widget build(BuildContext context) {
    final done = state.done.contains(step);
    final current = state.current == step;
    final (title, sub) = _texts;
    final number = step.index + 1;

    if (current) {
      return Material(
        color: context.colors.emphasis,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(routinePaths[step]!),
          child: Container(
            // 큰 글씨에서도 넘치지 않도록 최소 높이 + 세로 여백
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: context.colors.onEmphasisAccent, width: 2),
                  ),
                  child: Text(
                    '$number',
                    style: sans(13, weight: FontWeight.w700, color: context.colors.onEmphasisAccent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: sans(15, weight: FontWeight.w600, color: context.colors.onEmphasis),
                      ),
                      SizedBox(height: 6),
                      ThinProgress(
                        _progress,
                        color: context.colors.onEmphasisAccent,
                        track: context.colors.onEmphasis.withValues(alpha: 0.2),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  _progress > 0 ? '이어서' : '시작',
                  style: sans(13, weight: FontWeight.w600, color: context.colors.onEmphasis),
                ),
                Icon(Icons.chevron_right_rounded, color: context.colors.onEmphasis, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: done ? Colors.transparent : context.colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(routinePaths[step]!),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 60),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (done)
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: context.colors.success,
                    child: Icon(Icons.check_rounded, size: 17, color: context.colors.card),
                  )
                else
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: context.colors.lineStrong, width: 1.5),
                    ),
                    child: Text(
                      '$number',
                      style: sans(13, weight: FontWeight.w600, color: context.colors.ink2),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: done
                            ? sans(15, weight: FontWeight.w600, color: context.colors.ink2).copyWith(
                                decoration: TextDecoration.lineThrough,
                                decorationColor: context.colors.lineStrong,
                              )
                            : sans(15, weight: FontWeight.w600),
                      ),
                      if (!done) Text(sub, style: sans(12, color: context.colors.ink2)),
                    ],
                  ),
                ),
                if (done) Text('완료', style: sans(12, color: context.colors.ink2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelStrip extends StatelessWidget {
  const _LevelStrip({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final level = state.profile.overall;
    return Material(
      color: context.colors.sand,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/level-result'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(level.label, style: serif(24, weight: 600, color: context.colors.penBlue)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          level.isMax ? '최고 단계' : '다음 단계 ${level.next.label}까지',
                          style: sans(12, weight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text('${(level.progressToNext * 100).round()}%', style: sans(12, color: context.colors.ink2)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ThinProgress(
                      level.progressToNext,
                      height: 6,
                      color: context.colors.penBlue,
                      track: context.colors.sandDeep,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
