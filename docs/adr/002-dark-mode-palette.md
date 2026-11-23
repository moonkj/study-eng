# ADR 002: 다크 모드 — 팔레트 교체 방식

- 상태: 채택 (2026-11-22, 페르소나 8라운드) → 2026-11-24 개정: 아래 "대안"의 ThemeExtension 방식으로 전환

## 배경
A안 "따뜻한 종이 노트"의 색은 `AppColors.xxx` 정적 상수로 화면 곳곳(약 280곳)에서 `const` 위젯 안에 쓰였다.
다크 모드를 넣으려면 같은 이름이 테마에 따라 다른 값을 내야 한다.

## 결정
- `AppPalette`(light: 종이, dark: 밤의 종이) 두 벌을 두고, `AppColors.xxx` 는 지금 팔레트 값을 돌려주는 getter 로 바꾼다.
- 테마는 설정(`AppSettings.theme`: system / light / dark)과 휴대폰 밝기로 정하고, `TodayeApp.build` 에서 `AppColors.use()` 후 `MaterialApp.builder` 안을 `KeyedSubtree(ValueKey(dark))` 로 감싸 화면을 새로 만든다. 위치는 go_router 가 유지한다.
- 색이 들어간 `const` 위젯 표현식은 `const` 를 뗐다. 기본값이 색인 생성자(PaperCard, Tag, ThinProgress)는 `Color?` + 초기화 목록으로 바꿨다.
- 하드코딩 색은 토큰(`muted`, `mutedSoft`, `dotIdle`, `onInkSoft`, `sheetShadow`)으로 옮겼다.

## 대안
- `ThemeExtension<AppColorsExt>` + `Theme.of(context)`: 정석이지만 모든 호출부에 context 가 필요해 변경량이 크다. 화면이 늘어나면 이쪽으로 옮길 수 있게 이름은 그대로 둔다.

## 결과
- 테마를 바꾸면 진행 중인 화면의 로컬 상태(예: 단어 카드 뒤집힘)는 초기화된다. 자주 바꾸는 설정이 아니라 받아들인다.
- `const` 위젯이 줄어 리빌드 비용이 약간 늘지만 화면 규모에서 체감되지 않는다.
- 움직임은 `AppMotion` 토큰과 `motion(context, d)` 로 통일하고, '동작 줄이기'가 켜져 있으면 즉시 바뀐다.

## 개정 (2026-11-24): ThemeExtension 으로 전환
테마를 바꿀 때 `KeyedSubtree(ValueKey(dark))` 로 화면 전체를 새로 만들면서 뒤집은 단어 카드 같은 로컬 상태가 초기화되는 문제가 있어, 위 "대안"의 ThemeExtension 방식을 채택했다.

- `AppPalette extends ThemeExtension<AppPalette>` (copyWith·lerp). `buildAppTheme(AppPalette)` 가 팔레트로 테마를 만들고 `extensions` 에 등록한다.
- `MaterialApp` 에 `theme: buildAppTheme(AppPalette.light)`, `darkTheme: buildAppTheme(AppPalette.dark)`, `themeMode`(설정 system/light/dark)를 넘긴다. 휴대폰 밝기 변화는 MaterialApp 이 처리하므로 `didChangePlatformBrightness` 처리와 `KeyedSubtree` 는 없앴다.
- 화면 코드는 `context.colors.ink` 처럼 읽는다 (`extension AppColorsX on BuildContext`). 전역 가변 `AppColors` 는 삭제했다.
- `serif()` / `sans()` 는 `color` 를 비우면 주변 글자색(테마 본문색 = ink)을 물려받는다. 칩(라벨 기본색이 ink2)처럼 주변색이 ink 가 아닌 곳은 `color` 를 직접 넘긴다.
- `AppShadow.card(palette)` 는 팔레트를 받는다. `PaperCard`·`Tag`·`ThinProgress` 의 색 기본값은 `build` 에서 정한다(다시 `const` 생성 가능). `CustomPainter` 는 팔레트를 받고 `shouldRepaint` 에서 비교한다.
- 결과: 테마를 바꿔도 화면 위치와 로컬 상태가 그대로이고 색만 바뀐다(테마 전환은 MaterialApp 의 짧은 색 보간 애니메이션으로 바뀐다). 색 값은 그대로다.
