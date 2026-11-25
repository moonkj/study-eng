import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// 구역 제목 줄: 제목(headline 17) + 오른쪽 보조 글(caption) 또는 링크. 기본 위 32 · 아래 12.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.action,
    this.padding = const EdgeInsets.only(top: AppSpace.xxxl, bottom: AppSpace.md),
  });

  final String title;

  /// 오른쪽 보조 글 ("1/4 · 남은 11분")
  final String? trailing;

  /// 오른쪽 링크 버튼 등 (trailing 보다 우선)
  final Widget? action;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Semantics(header: true, child: Text(title, style: AppType.headline())),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  action ??
                  (trailing == null
                      ? const SizedBox.shrink()
                      : Text(
                          trailing!,
                          textAlign: TextAlign.right,
                          style: AppType.caption(color: context.colors.ink2),
                        )),
            ),
          ),
        ],
      ),
    );
  }
}
