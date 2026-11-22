import 'package:material_ui/material_ui.dart';

/// A안 "따뜻한 종이 노트" 색 팔레트. 밝은 종이(light)와 밤의 종이(dark) 두 벌.
/// 값은 docs/design/design-system.md 와 Claude Design 캔버스(A 페이지)를 따른다.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.paper,
    required this.card,
    required this.line,
    required this.lineStrong,
    required this.sand,
    required this.sandDeep,
    required this.track,
    required this.ink,
    required this.ink2,
    required this.inkSoft,
    required this.penBlue,
    required this.penBlueDark,
    required this.penBlueTint,
    required this.penBlueSoft,
    required this.highlighter,
    required this.success,
    required this.successTint,
    required this.error,
    required this.errorTint,
    required this.ember,
    required this.caution,
    required this.muted,
    required this.mutedSoft,
    required this.dotIdle,
    required this.onInkSoft,
  });

  final Brightness brightness;
  final Color paper;
  final Color card;
  final Color line;
  final Color lineStrong;
  final Color sand;
  final Color sandDeep;
  final Color track;
  final Color ink;
  final Color ink2;
  final Color inkSoft;
  final Color penBlue;
  final Color penBlueDark;
  final Color penBlueTint;
  final Color penBlueSoft;
  final Color highlighter;
  final Color success;
  final Color successTint;
  final Color error;
  final Color errorTint;
  final Color ember;
  final Color caution;
  final Color muted;
  final Color mutedSoft;
  final Color dotIdle;
  final Color onInkSoft;

  static const light = AppPalette(
    brightness: Brightness.light,
    paper: Color(0xFFF5F0E6),
    card: Color(0xFFFFFDF8),
    line: Color(0xFFE4DCCB),
    lineStrong: Color(0xFFB8AE9C),
    sand: Color(0xFFE9E1D1),
    sandDeep: Color(0xFFD6CCB8),
    track: Color(0xFFDDD3C1),
    ink: Color(0xFF1F1D1A),
    ink2: Color(0xFF5F584D),
    inkSoft: Color(0xFF3D3830),
    penBlue: Color(0xFF2C4A7A),
    penBlueDark: Color(0xFF1E3558),
    penBlueTint: Color(0xFFEAEFF6),
    penBlueSoft: Color(0xFFB9C6DA),
    highlighter: Color(0xFFF3DB7A),
    success: Color(0xFF3F6B4A),
    successTint: Color(0xFFEEF3EC),
    error: Color(0xFFA8432F),
    errorTint: Color(0xFFF8ECE7),
    ember: Color(0xFFB4532A),
    caution: Color(0xFF8A5A12),
    muted: Color(0xFFEDE6D8),
    mutedSoft: Color(0xFFF7F2E8),
    dotIdle: Color(0xFFCFC5B2),
    onInkSoft: Color(0xFFDDD3C1),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    paper: Color(0xFF181613),
    card: Color(0xFF221F1B),
    line: Color(0xFF37322B),
    lineStrong: Color(0xFF5C5448),
    sand: Color(0xFF2E2A24),
    sandDeep: Color(0xFF3B352D),
    track: Color(0xFF3A352E),
    ink: Color(0xFFF1EBDF),
    ink2: Color(0xFFB2A898),
    inkSoft: Color(0xFFDAD2C3),
    penBlue: Color(0xFF9EB7E2),
    penBlueDark: Color(0xFFC6D5EF),
    penBlueTint: Color(0xFF222D40),
    penBlueSoft: Color(0xFF3E5274),
    highlighter: Color(0xFF8C7424),
    success: Color(0xFF8DC39B),
    successTint: Color(0xFF1E2B21),
    error: Color(0xFFEC957F),
    errorTint: Color(0xFF3A221C),
    ember: Color(0xFFE58D60),
    caution: Color(0xFFE2B566),
    muted: Color(0xFF2A2621),
    mutedSoft: Color(0xFF25221E),
    dotIdle: Color(0xFF4A443B),
    onInkSoft: Color(0xFF4A443B),
  );
}

/// 화면 코드에서 쓰는 색 토큰. 지금 테마(밝게/어둡게)의 팔레트 값을 돌려준다.
/// 테마가 바뀌면 앱이 화면을 다시 만든다 (app.dart).
abstract final class AppColors {
  static AppPalette _p = AppPalette.light;
  static AppPalette get palette => _p;
  static bool get isDark => _p.brightness == Brightness.dark;
  static void use(AppPalette p) => _p = p;

  static Color get paper => _p.paper;
  static Color get card => _p.card;
  static Color get line => _p.line;
  static Color get lineStrong => _p.lineStrong;
  static Color get sand => _p.sand;
  static Color get sandDeep => _p.sandDeep;
  static Color get track => _p.track;
  static Color get ink => _p.ink;
  static Color get ink2 => _p.ink2;
  static Color get inkSoft => _p.inkSoft;
  static Color get penBlue => _p.penBlue;
  static Color get penBlueDark => _p.penBlueDark;
  static Color get penBlueTint => _p.penBlueTint;
  static Color get penBlueSoft => _p.penBlueSoft;
  static Color get highlighter => _p.highlighter;
  static Color get success => _p.success;
  static Color get successTint => _p.successTint;
  static Color get error => _p.error;
  static Color get errorTint => _p.errorTint;
  static Color get ember => _p.ember;
  static Color get caution => _p.caution;

  /// 빈 칸·비활성 배경 (달력 빈 날, 카드 뒤 겹침)
  static Color get muted => _p.muted;

  /// 더 옅은 비활성 배경
  static Color get mutedSoft => _p.mutedSoft;

  /// 선택 안 된 점·보조 표시
  static Color get dotIdle => _p.dotIdle;

  /// 잉크색 배경 위 보조 글자
  static Color get onInkSoft => _p.onInkSoft;

  /// 결과 시트 그림자
  static Color get sheetShadow => isDark ? const Color(0x80000000) : const Color(0x4D3C2D14);
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
  static List<BoxShadow> get card => [
    BoxShadow(color: AppColors.line, offset: const Offset(0, 1)),
    BoxShadow(
      color: AppColors.isDark ? const Color(0x66000000) : const Color(0x403C2D14),
      offset: const Offset(0, 12),
      blurRadius: 24,
      spreadRadius: -16,
    ),
  ];
}

/// 움직임 토큰. 휴대폰의 '동작 줄이기'가 켜져 있으면 [motion] 이 0 을 돌려 즉시 바뀐다.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

/// 동작 줄이기 설정을 반영한 애니메이션 시간
Duration motion(BuildContext context, Duration d) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
