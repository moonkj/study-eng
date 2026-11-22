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

## 규칙
- 앱 코드에 LLM API 키를 넣지 않는다. AI 호출은 모두 Cloud Functions 경유.
- 구조: `lib/{app,core,data,features/<name>/{data,domain,presentation}}`.
- 상태관리 Riverpod, 라우팅 go_router, 로컬 DB Drift, 모델 freezed.
- UI 문자열은 l10n(ARB, 기본 ko), 색·폰트·간격은 `lib/core/theme` 토큰만 사용.
- 변경 후 `flutter analyze` / `flutter test` 통과 확인.
- 설계 결정은 `docs/adr/`에 기록.
