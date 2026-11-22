# ADR 002: 다크 모드 — 팔레트 교체 방식

- 상태: 채택 (2026-11-22, 페르소나 8라운드)

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
