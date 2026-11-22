import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// 한글 UI 글꼴.
const kSans = 'IBMPlexSansKR';

/// 영어 표현·예문용 세리프 글꼴 (가변 폰트).
const kSerif = 'Newsreader';

/// 영어 세리프 텍스트 스타일. 가변 폰트라 굵기는 wght 축으로 지정한다.
TextStyle serif(
  double size, {
  int weight = 400,
  Color color = AppColors.ink,
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

/// 한글 산세리프 텍스트 스타일.
TextStyle sans(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
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

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kSans,
    scaffoldBackgroundColor: AppColors.paper,
    colorScheme: const ColorScheme.light(
      primary: AppColors.ink,
      onPrimary: AppColors.card,
      secondary: AppColors.penBlue,
      onSecondary: AppColors.card,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      error: AppColors.error,
      outline: AppColors.line,
    ),
    // 종이 질감에 맞게 반짝이(InkSparkle) 대신 잔잔한 물결
    splashFactory: InkRipple.splashFactory,
    highlightColor: const Color(0x1FF3DB7A),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink, fontFamily: kSans),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.ink,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.card,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: sans(16, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(56),
        side: const BorderSide(color: AppColors.ink, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: sans(15, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink2,
        minimumSize: const Size(44, 44),
        textStyle: sans(14, weight: FontWeight.w500),
      ),
    ),
  );
}
