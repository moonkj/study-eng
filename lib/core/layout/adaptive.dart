import 'package:material_ui/material_ui.dart';

/// 화면 폭 구간. iPad 세로(768~834), 가로(1024~1366), Split View(320~~700)까지 대응한다.
enum WindowSize {
  /// 휴대폰, iPad Slide Over/좁은 Split View (< 600)
  compact,

  /// iPad 세로, 반반 Split View (600 ~ 1023)
  medium,

  /// iPad 가로, 큰 화면 (≥ 1024)
  expanded;

  static WindowSize of(double width) => width >= 1024
      ? expanded
      : width >= 600
      ? medium
      : compact;

  bool get isCompact => this == compact;
  bool get isWide => this != compact;
}

extension AdaptiveContext on BuildContext {
  WindowSize get windowSize => WindowSize.of(MediaQuery.sizeOf(this).width);
}

/// 내용 폭을 읽기 좋은 너비로 제한하고 가운데 둔다.
/// 휴대폰에서는 아무것도 하지 않는다.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 스크롤 목록의 좌우 여백: 넓은 화면에서는 내용이 [maxWidth] 를 넘지 않게 여백을 키운다.
/// (목록 자체는 화면 전체 폭이라 어디서든 스크롤된다)
EdgeInsets readablePadding(
  BuildContext context, {
  double maxWidth = 720,
  double top = 20,
  double bottom = 24,
  double side = 24,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final h = ((width - maxWidth) / 2).clamp(side, double.infinity);
  return EdgeInsets.fromLTRB(h, top, h, bottom);
}
