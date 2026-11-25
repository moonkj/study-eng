import 'package:material_ui/material_ui.dart';

import '../../data/toeic.dart' show toeicLevels;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 토스 등급 눈금 (NL … AL).
/// 지금 위치(점, 범위면 굵은 막대) · 목표(세로선 + "목표" 글자) · 지난번(빈 동그라미).
/// 등급별 색은 쓰지 않는다: 지금 등급은 굵은 글자, 목표는 선 위치와 글자로 읽는다.
/// 스크린리더에는 한 문장 요약만 읽힌다 ([describe]).
class LevelScale extends StatelessWidget {
  const LevelScale({super.key, this.current, this.currentHigh, this.target, this.previous, this.levels = toeicLevels});

  /// 지금 예상 등급 (범위면 아래쪽). 비우면 기록 없음.
  final String? current;

  /// 지금 예상 범위 위쪽 등급
  final String? currentHigh;

  /// 목표 등급
  final String? target;

  /// 지난번 등급
  final String? previous;

  final List<String> levels;

  int _idx(String? l) => l == null ? -1 : levels.indexOf(l.toUpperCase());

  /// 스크린리더 요약 문장. 예: "등급 눈금. 지금 예상 IM2에서 IM3, 목표 IM3, 목표까지 1단계, 지난번 IM1"
  static String describe({
    String? current,
    String? currentHigh,
    String? target,
    String? previous,
    List<String> levels = toeicLevels,
  }) {
    int idx(String? l) => l == null ? -1 : levels.indexOf(l.toUpperCase());
    final parts = <String>[];
    final lo = idx(current);
    final hi = idx(currentHigh);
    if (lo < 0) {
      parts.add('아직 예상 등급 없음');
    } else if (hi > lo) {
      parts.add('지금 예상 $current에서 $currentHigh');
    } else {
      parts.add('지금 예상 $current');
    }
    final t = idx(target);
    if (t >= 0) {
      parts.add('목표 $target');
      if (lo >= 0) {
        final best = hi > lo ? hi : lo;
        parts.add(best >= t ? '목표 달성' : '목표까지 ${t - best}단계');
      }
    }
    if (idx(previous) >= 0) parts.add('지난번 $previous');
    return '등급 눈금. ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lo = _idx(current);
    final hiRaw = _idx(currentHigh);
    final hi = hiRaw > lo ? hiRaw : lo;
    final t = _idx(target);
    final p = _idx(previous);

    return Semantics(
      label: describe(current: current, currentHigh: currentHigh, target: target, previous: previous, levels: levels),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < levels.length; i++)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      levels[i],
                      style: lo >= 0 && i >= lo && i <= hi
                          ? AppType.caption(weight: FontWeight.w700, color: c.ink)
                          : AppType.caption(color: c.ink2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          SizedBox(
            height: 20,
            child: CustomPaint(
              painter: _ScalePainter(
                count: levels.length,
                lo: lo,
                hi: hi,
                target: t,
                previous: p,
                track: c.track,
                mark: c.ink,
                targetColor: c.target,
                card: c.card,
              ),
            ),
          ),
          if (t >= 0)
            Row(
              children: [
                for (var i = 0; i < levels.length; i++)
                  Expanded(
                    child: i == t
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('목표', style: AppType.micro(color: c.ink2)),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ScalePainter extends CustomPainter {
  _ScalePainter({
    required this.count,
    required this.lo,
    required this.hi,
    required this.target,
    required this.previous,
    required this.track,
    required this.mark,
    required this.targetColor,
    required this.card,
  });

  final int count, lo, hi, target, previous;
  final Color track, mark, targetColor, card;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / count;
    double x(int i) => cell * (i + 0.5);
    final y = size.height / 2;
    canvas.drawLine(
      Offset(x(0), y),
      Offset(x(count - 1), y),
      Paint()
        ..color = track
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(Offset(x(i), y), 2, Paint()..color = track);
    }
    if (target >= 0) {
      canvas.drawLine(
        Offset(x(target), 0),
        Offset(x(target), size.height),
        Paint()
          ..color = targetColor
          ..strokeWidth = 2,
      );
    }
    if (previous >= 0) {
      canvas.drawCircle(Offset(x(previous), y), 5, Paint()..color = card);
      canvas.drawCircle(
        Offset(x(previous), y),
        5,
        Paint()
          ..color = mark.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    if (lo >= 0) {
      if (hi > lo) {
        canvas.drawLine(
          Offset(x(lo), y),
          Offset(x(hi), y),
          Paint()
            ..color = mark
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(Offset(x(hi), y), 6, Paint()..color = mark);
    }
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.lo != lo ||
      old.hi != hi ||
      old.target != target ||
      old.previous != previous ||
      old.count != count ||
      old.mark != mark ||
      old.track != track;
}
