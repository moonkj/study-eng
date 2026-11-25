import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 빈 상태: 아이콘 + 한 줄(다음 행동) + 걸리는 시간 + 행동 버튼.
/// "아직 없어요"로 끝내지 않고 무엇을 하면 채워지는지, 얼마나 걸리는지를 같이 보여 준다.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.time,
    this.actionLabel,
    this.onAction,
    this.centered = false,
  });

  final IconData icon;

  /// 다음 행동 한 줄 ("첫 모의고사로 지금 위치를 확인해요")
  final String message;

  /// 걸리는 시간 ("약 20분")
  final String? time;

  /// 행동 버튼 글자 ("모의고사 보기"). [onAction] 이 없으면 버튼을 그리지 않는다.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 가운데 정렬 (화면 전체가 빈 경우)
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = time == null ? message : '$message · $time';
    final text = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 20, color: c.penBlue),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          child: Text(line, style: AppType.callout(color: c.ink2, height: 1.5)),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        text,
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(actionLabel!),
          ),
        ],
      ],
    );
  }
}
