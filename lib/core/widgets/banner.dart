import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// [AppBanner] 종류: 안내(모래색) / 잘됨(옅은 초록) / 주의(옅은 빨강)
enum BannerKind { info, success, warn }

/// 화면 위 알림 한 장 (기본 팩 안내·이어서 하기·목표 달성 등).
/// 아이콘 + 한두 줄 + 행동 버튼 최대 2개. Flutter 의 `Banner` 와 이름이 겹쳐 `AppBanner` 로 부른다.
/// 종류는 색뿐 아니라 아이콘과 스크린리더 앞말("안내"/"완료"/"주의")로도 알린다.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.kind = BannerKind.info,
    this.title,
    this.icon,
    this.actions = const [],
  }) : assert(actions.length <= 2, '행동 버튼은 최대 2개');

  final String message;
  final BannerKind kind;

  /// 굵은 첫 줄 (있으면 버튼이 아래 줄로 내려간다)
  final String? title;

  /// 비우면 종류별 기본 아이콘
  final IconData? icon;

  /// TextButton/FilledButton 등. FilledButton 은 테마 최소 폭이 화면 폭이라 Expanded 로 감싸야 한다.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, defaultIcon, spoken) = switch (kind) {
      BannerKind.info => (c.sand, c.ink2, Icons.info_outline_rounded, '안내'),
      BannerKind.success => (c.successTint, c.success, Icons.check_circle_outline_rounded, '완료'),
      BannerKind.warn => (c.errorTint, c.error, Icons.error_outline_rounded, '주의'),
    };
    final iconWidget = Icon(icon ?? defaultIcon, size: title == null ? 18 : 22, color: fg);
    final stacked = title != null || actions.length > 1;

    final Widget body;
    if (!stacked) {
      body = Row(
        children: [
          iconWidget,
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(message, style: AppType.callout(height: 1.45))),
          ...actions,
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconWidget,
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(title!, style: AppType.body(weight: FontWeight.w700)),
                      const SizedBox(height: AppSpace.xs),
                    ],
                    Text(message, style: AppType.callout(color: title != null ? c.ink2 : null, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.sm), actions[i]],
              ],
            ),
          ],
        ],
      );
    }

    return Semantics(
      container: true,
      label: spoken,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          actions.isEmpty ? AppSpace.lg : AppSpace.sm,
          stacked && actions.isNotEmpty ? AppSpace.sm : AppSpace.md,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.row)),
        child: body,
      ),
    );
  }
}
