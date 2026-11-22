import 'package:material_ui/material_ui.dart';

/// A안 "따뜻한 종이 노트" 디자인 토큰.
/// 값은 docs/design/design-system.md 와 Claude Design 캔버스(A 페이지)를 따른다.
abstract final class AppColors {
  static const paper = Color(0xFFF5F0E6);
  static const card = Color(0xFFFFFDF8);
  static const line = Color(0xFFE4DCCB);
  static const lineStrong = Color(0xFFB8AE9C);
  static const sand = Color(0xFFE9E1D1);
  static const sandDeep = Color(0xFFD6CCB8);
  static const track = Color(0xFFDDD3C1);

  static const ink = Color(0xFF1F1D1A);
  static const ink2 = Color(0xFF5F584D);
  static const inkSoft = Color(0xFF3D3830);

  static const penBlue = Color(0xFF2C4A7A);
  static const penBlueDark = Color(0xFF1E3558);
  static const penBlueTint = Color(0xFFEAEFF6);
  static const penBlueSoft = Color(0xFFB9C6DA);

  static const highlighter = Color(0xFFF3DB7A);

  static const success = Color(0xFF3F6B4A);
  static const successTint = Color(0xFFEEF3EC);
  static const error = Color(0xFFA8432F);
  static const errorTint = Color(0xFFF8ECE7);
  static const ember = Color(0xFFB4532A);
  static const caution = Color(0xFF8A5A12);
}

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const gutter = 24.0;
}

abstract final class AppRadius {
  static const chip = 12.0;
  static const button = 16.0;
  static const card = 20.0;
  static const hero = 24.0;
  static const sheet = 28.0;
}

abstract final class AppShadow {
  static const card = [
    BoxShadow(color: AppColors.line, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x403C2D14), offset: Offset(0, 12), blurRadius: 24, spreadRadius: -16),
  ];
}
