import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// 한글 UI 글꼴.
const kSans = 'IBMPlexSansKR';

/// 영어 표현·예문용 세리프 글꼴 (가변 폰트).
const kSerif = 'Newsreader';

/// 영어 세리프 텍스트 스타일. 가변 폰트라 굵기는 wght 축으로 지정한다.
/// [color] 를 비우면 주변 글자색(테마 본문색 = ink)을 물려받는다.
TextStyle serif(
  double size, {
  int weight = 400,
  Color? color,
  bool italic = false,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: kSerif,
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
    fontVariations: [FontVariation('wght', weight.toDouble()), FontVariation('opsz', size.clamp(6, 72).toDouble())],
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// 한글 산세리프 텍스트 스타일. [color] 를 비우면 주변 글자색(테마 본문색 = ink)을 물려받는다.
TextStyle sans(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: kSans,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// 글자 크기 체계. 한글(산세리프) 8단계 + 영어(세리프) 6단계만 쓴다.
/// 화면 코드는 `sans()/serif()` 에 숫자를 직접 넣지 말고 이 단계를 고른다. 예: `AppType.body(color: c.ink2)`.
/// 크기는 고정이고 굵기·색·줄 높이·자간·기울임만 바꿀 수 있다 (시스템 글자 크기 설정은 그대로 반영된다).
abstract final class AppType {
  // ── 한글 ──
  /// 34/700 — 화면의 가장 큰 숫자·문장
  static TextStyle display({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(34, weight: weight ?? FontWeight.w700, color: color, height: height, letterSpacing: letterSpacing ?? -0.5);

  /// 26/700 — 화면 제목
  static TextStyle title1({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(26, weight: weight ?? FontWeight.w700, color: color, height: height, letterSpacing: letterSpacing ?? -0.5);

  /// 20/700 — 카드·단계 제목
  static TextStyle title2({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(20, weight: weight ?? FontWeight.w700, color: color, height: height, letterSpacing: letterSpacing);

  /// 17/600 — 구역 제목(SectionHeader)
  static TextStyle headline({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(17, weight: weight ?? FontWeight.w600, color: color, height: height, letterSpacing: letterSpacing);

  /// 15/400 — 본문
  static TextStyle body({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(15, weight: weight ?? FontWeight.w400, color: color, height: height, letterSpacing: letterSpacing);

  /// 14/400 — 설명 문장
  static TextStyle callout({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(14, weight: weight ?? FontWeight.w400, color: color, height: height, letterSpacing: letterSpacing);

  /// 12/500 — 부제·보조 정보
  static TextStyle caption({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(12, weight: weight ?? FontWeight.w500, color: color, height: height, letterSpacing: letterSpacing);

  /// 11/600 — 아주 작은 라벨(눈금·출처)
  static TextStyle micro({FontWeight? weight, Color? color, double? height, double? letterSpacing}) =>
      sans(11, weight: weight ?? FontWeight.w600, color: color, height: height, letterSpacing: letterSpacing);

  // ── 영어(세리프) ──
  /// 44/500 — 단어 카드·결과 등급
  static TextStyle enDisplay({int? weight, Color? color, bool italic = false, double? height, double? letterSpacing}) =>
      serif(44, weight: weight ?? 500, color: color, italic: italic, height: height, letterSpacing: letterSpacing);

  /// 30/500 — 오늘의 표현·문장 카드
  static TextStyle enHero({int? weight, Color? color, bool italic = false, double? height, double? letterSpacing}) =>
      serif(30, weight: weight ?? 500, color: color, italic: italic, height: height, letterSpacing: letterSpacing);

  /// 22/500 — 숫자 값·짧은 영어 제목
  static TextStyle enTitle({int? weight, Color? color, bool italic = false, double? height, double? letterSpacing}) =>
      serif(22, weight: weight ?? 500, color: color, italic: italic, height: height, letterSpacing: letterSpacing);

  /// 18/400 — 영어 본문(예문·질문)
  static TextStyle enBody({int? weight, Color? color, bool italic = false, double? height, double? letterSpacing}) =>
      serif(18, weight: weight ?? 400, color: color, italic: italic, height: height, letterSpacing: letterSpacing);

  /// 16/400 — 짧은 영어 인용·보조 문장
  static TextStyle enCallout({int? weight, Color? color, bool italic = false, double? height, double? letterSpacing}) =>
      serif(16, weight: weight ?? 400, color: color, italic: italic, height: height, letterSpacing: letterSpacing);

  /// 14/400 — 표 칸·작은 영어
  static TextStyle enCaption({int? weight, Color? color, bool italic = false, double? height, double? letterSpacing}) =>
      serif(14, weight: weight ?? 400, color: color, italic: italic, height: height, letterSpacing: letterSpacing);
}

/// 팔레트로 테마를 만든다. 팔레트는 ThemeExtension 으로 등록돼 `context.colors` 로 읽는다.
ThemeData buildAppTheme(AppPalette c) {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kSans,
    scaffoldBackgroundColor: c.paper,
    brightness: c.brightness,
    colorScheme: ColorScheme(
      brightness: c.brightness,
      primary: c.ink,
      onPrimary: c.card,
      secondary: c.penBlue,
      onSecondary: c.card,
      surface: c.paper,
      onSurface: c.ink,
      error: c.error,
      onError: c.card,
      outline: c.line,
      outlineVariant: c.line,
      onSurfaceVariant: c.ink2,
      surfaceContainerLowest: c.card,
      surfaceContainerLow: c.card,
      surfaceContainer: c.muted,
      surfaceContainerHigh: c.sandDeep,
      surfaceContainerHighest: c.sandDeep,
    ),
    // 종이 질감에 맞게 반짝이(InkSparkle) 대신 잔잔한 물결
    splashFactory: InkRipple.splashFactory,
    highlightColor: c.highlighter.withValues(alpha: 0.12),
    extensions: [c],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: kSans),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.ink,
    ),
    // 띄운 면(시트)은 다크에서 카드보다 한 단계 밝게
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.isDark ? c.muted : c.card,
      modalBackgroundColor: c.isDark ? c.muted : c.card,
      dragHandleColor: c.lineStrong,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.ink,
        foregroundColor: c.card,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: AppType.body(weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size.fromHeight(56),
        side: BorderSide(color: c.ink, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: AppType.body(weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink2,
        minimumSize: const Size(44, 44),
        textStyle: AppType.callout(weight: FontWeight.w500),
      ),
    ),
  );
}
