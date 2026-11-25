import 'package:material_ui/material_ui.dart';

/// A안 "따뜻한 종이 노트" 색 팔레트. 밝은 종이(light)와 밤의 종이(dark) 두 벌.
/// 값은 docs/design/design-system.md 와 Claude Design 캔버스(A 페이지)를 따른다.
class AppPalette extends ThemeExtension<AppPalette> {
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
    required this.emphasis,
    required this.onEmphasis,
    required this.onEmphasisAccent,
    required this.onEmphasisSoft,
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

  /// 빈 칸·비활성 배경 (달력 빈 날, 카드 뒤 겹침)
  final Color muted;

  /// 더 옅은 비활성 배경
  final Color mutedSoft;

  /// 선택 안 된 점·보조 표시
  final Color dotIdle;

  /// 잉크색 배경 위 보조 글자
  final Color onInkSoft;

  /// 강조 면(지금 할 루틴, 완료 카드, 오늘 칸)과 그 위의 글자
  final Color emphasis;
  final Color onEmphasis;
  final Color onEmphasisAccent;
  final Color onEmphasisSoft;

  bool get isDark => brightness == Brightness.dark;

  /// 토스 준비 시간 타이머 색 (= 펜 파랑)
  Color get timerPrep => penBlue;

  /// 토스 답하기 타이머 색 (= 불씨색)
  Color get timerSpeak => ember;

  /// 목표선 (잉크 50%). 등급별 색은 만들지 않는다 — 등급은 글자와 목표선 위치로 읽는다.
  Color get target => ink.withValues(alpha: 0.5);

  /// 결과 시트 그림자
  Color get sheetShadow => isDark ? const Color(0x80000000) : const Color(0x4D3C2D14);

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? paper,
    Color? card,
    Color? line,
    Color? lineStrong,
    Color? sand,
    Color? sandDeep,
    Color? track,
    Color? ink,
    Color? ink2,
    Color? inkSoft,
    Color? penBlue,
    Color? penBlueDark,
    Color? penBlueTint,
    Color? penBlueSoft,
    Color? highlighter,
    Color? success,
    Color? successTint,
    Color? error,
    Color? errorTint,
    Color? ember,
    Color? caution,
    Color? muted,
    Color? mutedSoft,
    Color? dotIdle,
    Color? onInkSoft,
    Color? emphasis,
    Color? onEmphasis,
    Color? onEmphasisAccent,
    Color? onEmphasisSoft,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      paper: paper ?? this.paper,
      card: card ?? this.card,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      sand: sand ?? this.sand,
      sandDeep: sandDeep ?? this.sandDeep,
      track: track ?? this.track,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      inkSoft: inkSoft ?? this.inkSoft,
      penBlue: penBlue ?? this.penBlue,
      penBlueDark: penBlueDark ?? this.penBlueDark,
      penBlueTint: penBlueTint ?? this.penBlueTint,
      penBlueSoft: penBlueSoft ?? this.penBlueSoft,
      highlighter: highlighter ?? this.highlighter,
      success: success ?? this.success,
      successTint: successTint ?? this.successTint,
      error: error ?? this.error,
      errorTint: errorTint ?? this.errorTint,
      ember: ember ?? this.ember,
      caution: caution ?? this.caution,
      muted: muted ?? this.muted,
      mutedSoft: mutedSoft ?? this.mutedSoft,
      dotIdle: dotIdle ?? this.dotIdle,
      onInkSoft: onInkSoft ?? this.onInkSoft,
      emphasis: emphasis ?? this.emphasis,
      onEmphasis: onEmphasis ?? this.onEmphasis,
      onEmphasisAccent: onEmphasisAccent ?? this.onEmphasisAccent,
      onEmphasisSoft: onEmphasisSoft ?? this.onEmphasisSoft,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      paper: Color.lerp(paper, other.paper, t)!,
      card: Color.lerp(card, other.card, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      sandDeep: Color.lerp(sandDeep, other.sandDeep, t)!,
      track: Color.lerp(track, other.track, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      penBlue: Color.lerp(penBlue, other.penBlue, t)!,
      penBlueDark: Color.lerp(penBlueDark, other.penBlueDark, t)!,
      penBlueTint: Color.lerp(penBlueTint, other.penBlueTint, t)!,
      penBlueSoft: Color.lerp(penBlueSoft, other.penBlueSoft, t)!,
      highlighter: Color.lerp(highlighter, other.highlighter, t)!,
      success: Color.lerp(success, other.success, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorTint: Color.lerp(errorTint, other.errorTint, t)!,
      ember: Color.lerp(ember, other.ember, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedSoft: Color.lerp(mutedSoft, other.mutedSoft, t)!,
      dotIdle: Color.lerp(dotIdle, other.dotIdle, t)!,
      onInkSoft: Color.lerp(onInkSoft, other.onInkSoft, t)!,
      emphasis: Color.lerp(emphasis, other.emphasis, t)!,
      onEmphasis: Color.lerp(onEmphasis, other.onEmphasis, t)!,
      onEmphasisAccent: Color.lerp(onEmphasisAccent, other.onEmphasisAccent, t)!,
      onEmphasisSoft: Color.lerp(onEmphasisSoft, other.onEmphasisSoft, t)!,
    );
  }

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
    emphasis: Color(0xFF1F1D1A),
    onEmphasis: Color(0xFFFFFDF8),
    onEmphasisAccent: Color(0xFFF3DB7A),
    onEmphasisSoft: Color(0xFFDDD3C1),
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
    highlighter: Color(0xFF6B5A22),
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
    emphasis: Color(0xFF3A3226),
    onEmphasis: Color(0xFFF1EBDF),
    onEmphasisAccent: Color(0xFFE8C766),
    onEmphasisSoft: Color(0xFFB2A898),
  );
}

/// 화면 코드에서 색 토큰을 읽는 곳. `context.colors.ink` 처럼 쓴다.
/// 팔레트는 테마(ThemeData.extensions)에 들어 있어, 테마가 바뀌면 의존하는 위젯만 다시 그린다 (상태는 유지).
extension AppColorsX on BuildContext {
  AppPalette get colors => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

/// 간격 토큰. 4·8·12·16·20·24·32·48 여덟 개만 쓴다 (2·6·10·14 같은 값은 가장 가까운 값으로).
abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 48.0;

  /// 화면 좌우 여백
  static const gutter = 24.0;

  /// 카드 안 여백
  static const card = 20.0;

  /// 행(ActionRow) 안 좌우 여백
  static const row = 16.0;
}

/// 모서리 토큰. `BorderRadius.circular(16)` 처럼 직접 쓰지 않는다.
abstract final class AppRadius {
  static const chip = 12.0;
  static const nav = 14.0;
  static const button = 16.0;
  static const row = 16.0;
  static const card = 20.0;
  static const hero = 24.0;
  static const sheet = 28.0;
}

abstract final class AppShadow {
  static List<BoxShadow> card(AppPalette c) => [
    BoxShadow(color: c.line, offset: const Offset(0, 1)),
    BoxShadow(
      color: c.isDark ? const Color(0x66000000) : const Color(0x403C2D14),
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
  static const celebrate = Duration(milliseconds: 700);
  static const count = Duration(milliseconds: 900);

  /// 토스 단계 전환 (준비→답하기 링 색·굵기 보간)
  static const phase = Duration(milliseconds: 240);

  /// 채점 점수 카운트업
  static const score = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
}

/// 동작 줄이기 설정을 반영한 애니메이션 시간
Duration motion(BuildContext context, Duration d) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
