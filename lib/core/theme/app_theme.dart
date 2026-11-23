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
        textStyle: sans(16, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size.fromHeight(56),
        side: BorderSide(color: c.ink, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: sans(15, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink2,
        minimumSize: const Size(44, 44),
        textStyle: sans(14, weight: FontWeight.w500),
      ),
    ),
  );
}
