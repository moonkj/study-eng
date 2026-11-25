import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'widgets.dart' show PaperCard;

/// 숫자 한 칸: 값(enTitle 22) + 라벨(caption) + 선택 변화(+n, 오를 때만).
/// 여러 개를 나란히 둘 때는 호출하는 쪽에서 Expanded 로 감싼다.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.delta, this.centered = false});

  final String value;
  final String label;

  /// 지난번보다 늘어난 양. 0 이하면 보이지 않는다 (하락은 숨김).
  final num? delta;

  /// 가운데 정렬 (완료 화면)
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = delta;
    final up = d != null && d > 0;
    final deltaText = up ? '+${d is double ? d.toStringAsFixed(1) : d}' : null;
    return Semantics(
      label: '$label $value${up ? ', $deltaText 늘었어요' : ''}',
      excludeSemantics: true,
      child: PaperCard(
        radius: AppRadius.row,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
        child: Column(
          crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(child: Text(value, style: AppType.enTitle())),
                if (deltaText != null) ...[
                  const SizedBox(width: AppSpace.xs),
                  Text(
                    deltaText,
                    style: AppType.caption(weight: FontWeight.w600, color: c.success),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              label,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: AppType.caption(color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
