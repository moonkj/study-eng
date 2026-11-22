import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/study_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/level.dart';
import '../../domain/study_log.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final now = ref.watch(clockProvider)();
    // 단어 카드 중 '알아요'(7일 간격) 이상까지 올라간 것을 외운 단어로 센다
    final knownWords = s.cards.values.where((c) => c.itemId.startsWith('w-') && c.stage >= 2).length;
    final records = s.log.values.toList();
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
                      style: sans(12, weight: FontWeight.w600, color: AppColors.success),
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
                        style: sans(13, color: AppColors.ink2, height: 1.5),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: CustomPaint(painter: _GrowthPainter(points: points)),
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
              _Stat(label: '최고 연속', value: '${computeLongestStreak(s.log.keys)}일'),
            ],
          ),
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
                    Text('${s.studiedDays.length}일 학습 · 연속 ${s.streakDays}일', style: sans(12, color: AppColors.ink2)),
                  ],
                ),
                const SizedBox(height: 10),
                _MonthGrid(now: now, studied: s.studiedDays),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('자동 조정 내역', style: sans(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (s.lastAdjustmentReasons.isEmpty)
            Text('첫 루틴을 끝내면 내일 학습을 어떻게 바꿨는지 알려드려요.', style: sans(13, color: AppColors.ink2)),
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
                      color: r.contains('말하기') ? AppColors.ember : AppColors.success,
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
            Text(label, style: sans(12, color: AppColors.ink2)),
            const SizedBox(height: 2),
            Text(value, style: serif(24, weight: 500)),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.now, required this.studied});
  final DateTime now;
  final Set<int> studied;

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
            child: Text(h, style: sans(10, color: AppColors.ink2)),
          ),
        for (var i = 0; i < lead; i++) const SizedBox.shrink(),
        for (var d = 1; d <= days; d++) _DayCell(day: d, today: now.day, studied: studied.contains(d)),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today, required this.studied});
  final int day;
  final int today;
  final bool studied;

  @override
  Widget build(BuildContext context) {
    final isToday = day == today;
    final future = day > today;
    final (bg, fg) = isToday
        ? (AppColors.ink, AppColors.highlighter)
        : future
        ? (Colors.transparent, AppColors.ink2)
        : studied
        ? (AppColors.penBlue, AppColors.card)
        : (const Color(0xFFEDE6D8), AppColors.ink2);
    return Semantics(
      label:
          '$day일, ${isToday
              ? '오늘'
              : future
              ? ''
              : studied
              ? '학습함'
              : '쉼'}',
      excludeSemantics: true,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: future ? Border.all(color: AppColors.track) : null,
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
              ),
          ],
        ),
      ),
    );
  }
}

/// 날짜별 레벨 점수 곡선
class _GrowthPainter extends CustomPainter {
  _GrowthPainter({required this.points});
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
    final grid = Paint()..color = const Color(0xFFEDE6D8);
    for (var i = 0; i < 3; i++) {
      final y = 8 + i * (size.height - 26) / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // 세로축: 최저/최고 레벨 라벨
    for (final (v, y) in [(maxV - 30, 8.0), (minV + 30, size.height - 26)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: Level(v.round()).label,
          style: sans(10, color: AppColors.ink2),
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
    canvas.drawPath(fill, Paint()..color = AppColors.penBlue.withValues(alpha: 0.07));
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.penBlue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final last = p(points.length - 1);
    canvas.drawCircle(last, 6, Paint()..color = AppColors.card);
    canvas.drawCircle(last, 4.5, Paint()..color = AppColors.penBlue);
    for (final i in {0, points.length - 1}) {
      final d = points[i].$1;
      final tp = TextPainter(
        text: TextSpan(
          text: '${d.month}/${d.day}',
          style: sans(10, color: AppColors.ink2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((p(i).dx - tp.width / 2).clamp(0, size.width - tp.width), size.height - 12));
    }
  }

  @override
  bool shouldRepaint(_GrowthPainter old) => old.points.length != points.length;
}
