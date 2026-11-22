import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/study_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/srs.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(studyProvider);
    final now = ref.watch(clockProvider)();
    final knownWords = 405 + s.wordRatings.values.where((r) => r == SelfRating.know).length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
                SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: CustomPaint(painter: _GrowthPainter(current: s.profile.overall.score.toDouble())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: '외운 단어', value: '$knownWords'),
              const SizedBox(width: 8),
              const _Stat(label: '퀴즈 정답률', value: '81%'),
              const SizedBox(width: 8),
              _Stat(label: '연속 학습', value: '${s.streakDays}일'),
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
        ? (Colors.transparent, const Color(0xFF8A8273))
        : studied
        ? (AppColors.penBlue, AppColors.card)
        : (const Color(0xFFEDE6D8), AppColors.ink2);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: future ? Border.all(color: AppColors.track) : null,
      ),
      child: Text(
        '$day',
        style: sans(11, weight: isToday ? FontWeight.w700 : FontWeight.w400, color: fg),
      ),
    );
  }
}

/// 3개월 레벨 변화 곡선 (현재는 최근 값만 실제, 이전 값은 기록 저장 기능이 붙으면 대체)
class _GrowthPainter extends CustomPainter {
  _GrowthPainter({required this.current});
  final double current;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [current - 300, current - 170, current - 60, current];
    final minV = points.first - 40;
    final maxV = current + 40;
    Offset p(int i) => Offset(
      24 + i * (size.width - 36) / (points.length - 1),
      size.height - 18 - (points[i] - minV) / (maxV - minV) * (size.height - 30),
    );
    final grid = Paint()..color = const Color(0xFFEDE6D8);
    for (var i = 0; i < 3; i++) {
      final y = 8 + i * (size.height - 26) / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
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
    const labels = ['9월', '10월', '', '11월'];
    for (var i = 0; i < labels.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: sans(10, color: AppColors.ink2),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p(i).dx - tp.width / 2, size.height - 12));
    }
  }

  @override
  bool shouldRepaint(_GrowthPainter old) => old.current != current;
}
