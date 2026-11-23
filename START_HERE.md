# todaye (오늘의 영어) — 새 PC에서 시작하기

AI 영어 선생님이 매일 회화 표현 3개·단어 10개·예문·복습 퀴즈를 챙겨 주는 Flutter 앱입니다.
이 폴더에는 지금까지의 코드와 작업 기록(git 히스토리 22개 커밋)이 모두 들어 있습니다.

## 1. GitHub(moonkj/study-eng)에 올리기
```bash
cd study-eng
git remote -v            # origin 이 https://github.com/moonkj/study-eng.git 인지 확인
git push -u origin main
```
- 저장소를 만들 때 README 등을 같이 만들어서 push 가 거절되면: `git push -u origin main --force`
  (그 저장소에 원래 있던 README 등은 사라집니다)

## 2. 개발 환경 준비
| 필요한 것 | 버전 | 확인 |
|---|---|---|
| Flutter SDK | 3.50 이상 | `flutter --version` |
| Xcode (아이폰·아이패드) | 최신 | Mac 만 |
| Android Studio (안드로이드) | 최신 | |
| Node.js (서버, 선택) | 20 이상 | `node -v` |

```bash
flutter pub get
flutter analyze          # 문제 없어야 함
flutter test             # 105개 통과해야 함
```

## 3. 앱 실행
```bash
flutter run -d chrome    # 브라우저 (음성 인식·알림은 안 됨)
flutter run              # 연결한 아이폰·아이패드·안드로이드
```
- 서버 없이도 기본 학습 팩으로 전부 동작합니다.
- 아이폰에 설치하는 방법: Xcode 로 `ios/Runner.xcworkspace` 를 열고 Signing 에서 내 Apple ID 팀 선택 → 기기 연결 → Run.

## 4. Claude 맞춤 학습(선택)
서버를 배포하면 매일 내 레벨에 맞는 팩을 Claude 가 만들어 줍니다. 자세한 순서: `docs/server.md`
```bash
cd functions && npm install && npm test     # 가짜 Claude 로 테스트 (비용 없음)
```
앱 실행 시 서버 주소와 토큰을 넘깁니다 (API 키는 절대 앱에 넣지 않습니다):
```bash
flutter run --dart-define=CONTENT_API_URL=https://...  --dart-define=CONTENT_API_TOKEN=...
```

## 5. Claude Code 로 이어서 작업하기
- 이 폴더에서 `claude` 를 실행하면 `CLAUDE.md`(프로젝트 규칙)와 `.claude/agents/`(팀 에이전트 7명 + 검토 페르소나 10명)가 자동으로 읽힙니다.
- 지금까지의 계획·결정·검토 기록:
  - `docs/PLAN.md` 전체 계획
  - `docs/level-system.md` 레벨 판단 방식
  - `docs/design/design-system.md` 디자인 (A안 "따뜻한 종이 노트")
  - `docs/adr/` 설계 결정 (저장소, 다크 모드)
  - `docs/persona-review.md` 페르소나 10라운드 검토와 반영 내역, 남은 과제

## 남은 과제 (다음 작업 후보)
- 실기기 확인: 마이크(음성 인식), 알림, 하드웨어 키보드
- 서버: 시도당 시간 제한(75초) 실측 후 조정, 웹 공개 시 Firebase 인증으로 전환
- 회상형 퀴즈, 처음 1~3일 분량 줄이기, A2 기본 팩, 색 토큰 ThemeExtension 전환
