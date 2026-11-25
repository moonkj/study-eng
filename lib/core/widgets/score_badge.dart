import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 토스 등급 칩. "IM2" 또는 범위 "IM2~IM3".
/// 목표 이상이면 체크 아이콘 + 초록 (색만으로 읽지 않게 아이콘과 스크린리더 문장을 함께).
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.level, this.upTo, this.met});

  /// 등급 (범위면 아래쪽)
  final String level;

  /// 범위 위쪽 등급. [level] 과 같거나 비우면 한 등급만 보인다.
  final String? upTo;

  /// 목표 이상인지. null 이면 목표와 비교하지 않는다.
  final bool? met;

  String get text => upTo == null || upTo == level ? level : '$level~$upTo';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ok = met == true;
    final fg = ok ? c.success : c.penBlue;
    final bg = ok ? c.successTint : c.penBlueTint;
    final spoken = upTo == null || upTo == level ? '등급 $level' : '등급 $level에서 $upTo';
    return Semantics(
      label: '$spoken${met == null ? '' : (ok ? ', 목표 이상' : ', 목표 미만')}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ok) ...[Icon(Icons.check_rounded, size: 14, color: fg), const SizedBox(width: AppSpace.xs)],
            Text(
              text,
              style: AppType.caption(weight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
