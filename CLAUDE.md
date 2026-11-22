# todaye — 오늘의 영어

AI 영어 선생님이 매일 회화 표현 3개·단어 10개·실생활 예문·복습 퀴즈를 챙겨주는 Flutter 앱.
전체 계획은 `docs/PLAN.md` 참고.

## 팀 에이전트 (`.claude/agents/`)
| 에이전트 | 언제 쓰나 |
|---|---|
| product-planner | 기능 범위·유저 스토리·수용 기준·마일스톤 |
| learning-content-expert | 커리큘럼, 콘텐츠 형식·품질 기준, AI 생성 결과 검수 |
| ux-designer | 화면 스펙, 디자인 토큰, 카피, 접근성 |
| flutter-architect | 구조·패키지·ADR, 구조 리뷰 |
| flutter-developer | 화면/기능 구현 + 테스트 |
| ai-backend-engineer | Cloud Functions + Claude API, 프롬프트, 비용, 보안 |
| qa-engineer | 테스트 케이스, 엣지 케이스, 최종 리뷰 |

기능 하나는 planner → (content, ux, architect) → developer/ai-backend → qa 순서로 진행한다.

## 검토 페르소나 10인 (`.claude/agents/persona-*.md`, 읽기 전용)
SLA 연구자 · 원어민 강사 · 한국인 학습 코치 · UX · UI · 접근성 · 습관 형성 · iPad · Flutter 엔지니어 · PM/QA.
큰 변경 뒤에는 관련 페르소나에게 검토를 맡긴다. 지난 검토와 반영 내역: `docs/persona-review.md`

## iPad
- 폭 구간: `lib/core/layout/adaptive.dart` (compact < 600 ≤ medium < 1024 ≤ expanded)
- 탭 화면은 `readablePadding`, 학습 화면은 라우터의 `_focused()` 가 680 폭으로 감싼다
- 학습 화면에는 하드웨어 키보드 단축키(`CallbackShortcuts`)를 단다

## 개발 명령
- `flutter analyze` / `flutter test` / `flutter run -d chrome`
- 서버: `cd functions && npm test` (가짜 Claude 클라이언트, 비용 없음). 서버 JSON 형식을 바꾸면 `npm run fixture` 로 앱 계약 테스트 픽스처도 갱신
- Flutter 3.50+: Material 위젯은 `package:material_ui/material_ui.dart` 로 import (flutter/material.dart 는 deprecated)
- 디자인은 A안 "따뜻한 종이 노트" 확정. 색·간격은 `lib/core/theme/tokens.dart`, 글꼴 스타일은 `serif()`(영어) / `sans()`(한글)

## 규칙
- 앱 코드에 LLM API 키를 넣지 않는다. AI 호출은 모두 Cloud Functions 경유.
- 구조: `lib/{app,core,domain,data,features/<name>}`. 레벨·SRS 같은 규칙은 `domain/`(순수 Dart)에 두고 테스트한다.
- 상태관리 Riverpod, 라우팅 go_router, 로컬 저장 shared_preferences(JSON, `AppStore` 인터페이스 뒤)
- 색·폰트·간격은 `lib/core/theme` 토큰만 사용. (UI 문자열 l10n 분리는 추후)
- 변경 후 `flutter analyze` / `flutter test` 통과 확인.
- 설계 결정은 `docs/adr/`에 기록.
