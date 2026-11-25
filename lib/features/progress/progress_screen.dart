import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/study_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

import 'package:go_router/go_router.dart';

import '../../data/models.dart' show kErrorTypeKo;
import '../../data/pack_source.dart' show weakErrorTypesOf;
import '../../domain/level.dart';
import '../../domain/mastery.dart';
import '../../domain/study_log.dart';
import '../../data/toeic.dart';
import '../../domain/toeic_weakness.dart';
import '../toeic/toeic_target.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final now = s.now; // 학습일 기준 (매달 1일 새벽에 제목과 달력이 어긋나지 않게)
    // 단어 카드 중 '알아요'(7일 간격) 이상까지 올라간 것을 외운 단어로 센다
    final knownWords = s.cards.values.where((c) => c.itemId.startsWith('w-') && c.stage >= 2).length;
    final records = s.log.values.where((r) => !r.mini).toList(); // 3분 루틴 날은 퀴즈가 없어 정답률에서 뺀다
    final accuracy = records.isEmpty ? null : records.map((r) => r.accuracy).reduce((a, b) => a + b) / records.length;
    final keys = s.log.keys.toList()..sort();
    final points = [
      for (final k in keys.length > 60 ? keys.sublist(keys.length - 60) : keys)
        (parseDateKey(k), s.log[k]!.levelScore.toDouble()),
    ];

    return SafeArea(
      child: ListView(
        padding: readablePadding(context, maxWidth: 680),
        children: [
          Text('기록', style: sans(26, weight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 14),
          PaperCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('레벨 성장', style: sans(14, weight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      '지금 ${s.profile.overall.label}',
                      style: sans(12, weight: FontWeight.w600, color: context.colors.success),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (points.length < 2)
                  SizedBox(
                    height: 110,
                    child: Center(
                      child: Text(
                        '루틴을 이틀 이상 끝내면\n레벨 변화가 여기에 그려져요',
                        textAlign: TextAlign.center,
                        style: sans(13, color: context.colors.ink2, height: 1.5),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _GrowthPainter(colors: context.colors, points: points),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: '외운 단어', value: '$knownWords'),
              const SizedBox(width: 8),
              _Stat(label: '퀴즈 정답률', value: accuracy == null ? '-' : '${(accuracy * 100).round()}%'),
              const SizedBox(width: 8),
              _Stat(label: '최고 연속', value: '${s.longestStreak}일'),
            ],
          ),
          if (weakErrorTypesOf(s.log, s.now).isNotEmpty) ...[
            const SizedBox(height: 12),
            PaperCard(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Text(
                '요즘 자주 틀리는 유형: ${weakErrorTypesOf(s.log, s.now).map((t) => kErrorTypeKo[t] ?? t).join(' · ')}\n다음 학습에서 이 유형을 조금 더 연습해요.',
                style: sans(13, height: 1.55),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _ToeicCard(state: s, ready: ref.watch(toeicBankProvider) != null),
          if (s.toeicLog.isNotEmpty || s.mocks.isNotEmpty) ...[const SizedBox(height: 12), _ToeicTypesCard(state: s)],
          const SizedBox(height: 12),
          _MyExpressionsCard(state: s),
          const SizedBox(height: 12),
          PaperCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${now.month}월', style: sans(14, weight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      '${s.studiedDays.length}일 학습 · 연속 ${s.streakDays}일',
                      style: sans(12, color: context.colors.ink2),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.weekend_outlined, size: 14, color: context.colors.ink2),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [
                          if (s.streak.restsLeft > 0) '쉬는 날 ${s.streak.restsLeft}개 (빠진 날을 자동으로 메워요)',
                          if (s.streak.daysToNextRest > 0) '${s.streak.daysToNextRest}일 더 하면 쉬는 날 1개',
                        ].join(' · '),
                        style: sans(12, color: context.colors.ink2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _MonthGrid(now: s.now, studied: s.studiedDays, rested: s.restDaysThisMonth),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('자동 조정 내역', style: sans(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (s.lastAdjustmentReasons.isEmpty)
            Text('첫 루틴을 끝내면 내일 학습을 어떻게 바꿨는지 알려드려요.', style: sans(13, color: context.colors.ink2)),
          for (final r in s.lastAdjustmentReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: r.contains('말하기') ? context.colors.ember : context.colors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(r, style: sans(13, height: 1.5))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PaperCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: sans(12, color: context.colors.ink2)),
            const SizedBox(height: 2),
            Text(value, style: serif(24, weight: 500)),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.now, required this.studied, required this.rested});
  final DateTime now;
  final Set<int> studied;
  final Set<int> rested;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(now.year, now.month, 1);
    final days = DateTime(now.year, now.month + 1, 0).day;
    final lead = first.weekday % 7; // 일요일 시작
    const heads = ['일', '월', '화', '수', '목', '금', '토'];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 5,
      crossAxisSpacing: 5,
      childAspectRatio: 1.25,
      children: [
        for (final h in heads)
          Center(
            child: Text(h, style: sans(10, color: context.colors.ink2)),
          ),
        for (var i = 0; i < lead; i++) const SizedBox.shrink(),
        for (var d = 1; d <= days; d++)
          _DayCell(day: d, today: now.day, studied: studied.contains(d), rested: rested.contains(d)),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today, required this.studied, this.rested = false});
  final int day;
  final int today;
  final bool studied;

  /// 쉬는 날로 연속 기록을 지킨 날
  final bool rested;

  @override
  Widget build(BuildContext context) {
    final isToday = day == today;
    final future = day > today;
    final (bg, fg) = isToday
        ? (context.colors.emphasis, context.colors.onEmphasisAccent)
        : future
        ? (Colors.transparent, context.colors.ink2)
        : studied
        // 밤의 종이에서는 밝은 파랑 타일이 눈부시지 않게 차분한 파랑에 잉크 글자
        ? (context.colors.isDark
              ? (context.colors.penBlueSoft, context.colors.ink)
              : (context.colors.penBlue, context.colors.card))
        : rested
        ? (context.colors.sand, context.colors.ink)
        : (context.colors.muted, context.colors.ink2);
    return Semantics(
      label:
          '$day일, ${isToday
              ? '오늘'
              : future
              ? ''
              : studied
              ? '학습함'
              : rested
              ? '쉬는 날 사용'
              : '안 함'}',
      excludeSemantics: true,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: future ? Border.all(color: context.colors.track) : null,
        ),
        // 색만으로 구분하지 않도록 학습한 날에는 점을 찍는다
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: sans(12, weight: isToday ? FontWeight.w700 : FontWeight.w400, color: fg),
            ),
            if (studied && !isToday)
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              )
            else if (rested && !isToday)
              Icon(Icons.weekend_outlined, size: 9, color: fg),
          ],
        ),
      ),
    );
  }
}

/// 날짜별 레벨 점수 곡선
class _GrowthPainter extends CustomPainter {
  _GrowthPainter({required this.colors, required this.points});
  final AppPalette colors;
  final List<(DateTime, double)> points;

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => p.$2).toList();
    final minV = values.reduce((a, b) => a < b ? a : b) - 30;
    final maxV = values.reduce((a, b) => a > b ? a : b) + 30;
    final first = points.first.$1;
    final span = points.last.$1.difference(first).inDays.clamp(1, 100000);
    Offset p(int i) => Offset(
      30 + points[i].$1.difference(first).inDays / span * (size.width - 42),
      size.height - 18 - (values[i] - minV) / (maxV - minV) * (size.height - 30),
    );
    final grid = Paint()..color = colors.muted;
    for (var i = 0; i < 3; i++) {
      final y = 8 + i * (size.height - 26) / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // 세로축: 최저/최고 레벨 라벨
    // 위아래가 같은 단계면(변화가 작은 기간) 한 번만 쓴다
    final top = Level((maxV - 30).round()).label, bottom = Level((minV + 30).round()).label;
    for (final (v, y) in [(maxV - 30, 8.0), if (top != bottom) (minV + 30, size.height - 26)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: Level(v.round()).label,
          style: sans(10, color: colors.ink2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 6));
    }
    final path = Path()..moveTo(p(0).dx, p(0).dy);
    for (var i = 1; i < points.length; i++) {
      final a = p(i - 1), b = p(i);
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(path)
      ..lineTo(p(points.length - 1).dx, size.height - 14)
      ..lineTo(p(0).dx, size.height - 14)
      ..close();
    canvas.drawPath(fill, Paint()..color = colors.penBlue.withValues(alpha: 0.07));
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.penBlue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final last = p(points.length - 1);
    canvas.drawCircle(last, 6, Paint()..color = colors.card);
    canvas.drawCircle(last, 4.5, Paint()..color = colors.penBlue);
    for (final i in {0, points.length - 1}) {
      final d = points[i].$1;
      final tp = TextPainter(
        text: TextSpan(
          text: '${d.month}/${d.day}',
          style: sans(10, color: colors.ink2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((p(i).dx - tp.width / 2).clamp(0, size.width - tp.width), size.height - 12));
    }
  }

  @override
  // 60일이 넘으면 개수는 같고 내용만 밀리므로 값까지 비교한다
  bool shouldRepaint(_GrowthPainter old) =>
      old.colors != colors ||
      old.points.length != points.length ||
      (points.isNotEmpty && (old.points.first != points.first || old.points.last != points.last));
}

/// '내 표현' 모음으로 가는 카드: 숙련 단계별 개수
class _MyExpressionsCard extends StatelessWidget {
  const _MyExpressionsCard({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final l in state.learned.values)
        if (l.kind == 'expression') l,
    ];
    final counts = {for (final m in Mastery.values) m: items.where((l) => masteryOf(state.cards[l.id]) == m).length};
    final done = counts[Mastery.graduated]! + counts[Mastery.mastered]!;
    return PaperCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.push('/my-expressions'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('내 표현 ${items.length}개', style: sans(14, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('익히는 중 ${counts[Mastery.learning]} · 졸업 $done', style: sans(12, color: context.colors.ink2)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.colors.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

/// 토스 유형별 최근 점수와 약점
class _ToeicTypesCard extends StatelessWidget {
  const _ToeicTypesCard({required this.state});
  final StudyState state;

  @override
  Widget build(BuildContext context) {
    final stats = typeStats(state.toeicLog, state.mocks);
    final weak = weakestType(stats);
    final weakIsBlock = weak != null && blockType.containsValue(weak);
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('토스 유형별 점수', style: sans(14, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('유형마다 최근 5번 평균 (루틴·모의고사)', style: sans(12, color: context.colors.ink2)),
          const SizedBox(height: 10),
          for (final type in toeicTypeKo.keys)
            _TypeRow(name: toeicTypeKo[type]!, stat: stats[type], weak: type == weak),
          if (weak != null) ...[
            const SizedBox(height: 6),
            Text(
              weakIsBlock
                  ? '${toeicTypeKo[weak]}이(가) 가장 약해요. 매일 루틴에 이틀에 한 번 더 나와요.'
                  : '${toeicTypeKo[weak]}이(가) 가장 약해요. 매일 루틴에 나오니 모범 답안을 따라 말해 보세요.',
              style: sans(13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.name, required this.stat, required this.weak});
  final String name;
  final TypeStat? stat;
  final bool weak;

  @override
  Widget build(BuildContext context) {
    final avg = stat?.average.round();
    return Semantics(
      label: avg == null ? '$name, 기록 없음' : '$name, 평균 $avg점${weak ? ', 약점' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 104, child: Text(name, style: sans(13))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (avg ?? 0) / 100,
                  minHeight: 8,
                  backgroundColor: context.colors.track,
                  color: weak ? context.colors.error : context.colors.success,
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                avg == null ? '-' : '$avg점',
                textAlign: TextAlign.right,
                style: sans(13, weight: weak ? FontWeight.w700 : FontWeight.w400),
              ),
            ),
            if (weak) ...[
              const SizedBox(width: 6),
              Tag('약점', color: context.colors.error, background: context.colors.errorTint),
            ],
          ],
        ),
      ),
    );
  }
}

/// 토스 목표와 모의고사 기록
class _ToeicCard extends StatelessWidget {
  const _ToeicCard({required this.state, required this.ready});
  final StudyState state;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final target = state.toeicTarget;
    final recent = state.mocks.reversed.take(5).toList();
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('토스 모의고사', style: sans(14, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('목표 ${targetLabel(target)}', style: sans(12, color: context.colors.ink2)),
          if (state.targetReached) ...[const SizedBox(height: 10), const TargetReachedCard()],
          const SizedBox(height: 6),
          if (recent.isEmpty)
            Text('아직 본 모의고사가 없어요.', style: sans(13, color: context.colors.ink2))
          else
            for (final m in recent)
              MockHistoryRow(
                date: '${parseDateKey(m.date).month}월 ${parseDateKey(m.date).day}일',
                level: m.level,
                average: m.average.round(),
                met: meetsTarget(
                  m.level,
                  ToeicTarget.values.firstWhere((t) => t.label == m.target, orElse: () => target),
                ),
              ),
          if (ready)
            Wrap(
              spacing: 8,
              children: [
                TextButton(onPressed: () => context.push('/toeic-mock'), child: const Text('모의고사 보기')),
                TextButton(onPressed: () => context.push('/toeic'), child: const Text('유형별로 연습하기')),
              ],
            ),
        ],
      ),
    );
  }
}
