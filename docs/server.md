# 학습 팩 서버 (Claude) 설정

앱은 매일 "오늘의 학습 팩"(표현 3 · 단어 10 · 따라 말하기 문장 · 퀴즈)을 내 서버에 요청하고,
서버가 Claude API 로 **내 레벨·약한 영역·복습할 항목**에 맞춘 팩을 만들어 돌려줍니다.
서버를 연결하지 않으면 앱은 기본 샘플 팩으로 동작합니다.

```
앱 ──POST /dailyPack (Bearer APP_TOKEN)──▶ Cloud Functions ──▶ Claude API (claude-opus-5-5)
   ◀────────────── 오늘의 팩 JSON ─────────┘   (API 키는 서버의 Secret Manager 에만)
```

## 서버가 하는 일 (`functions/src`)
- `schema.ts` — 요청 형식과 Claude 구조화 출력 스키마 (zod)
- `pack.ts` — 프롬프트, 규칙 검사(개수·단어 포함·중복·복습 누락 등), 실패 시 문제를 알려주고 1회 재시도
- `handler.ts` — 토큰 확인, 요청 검증, 오류 → HTTP 상태 코드
- `index.ts` — Firebase Cloud Functions 진입점 (서울 리전)
- `dev.ts` — 배포 없이 쓰는 로컬 서버

Claude 호출 설정: `claude-opus-5-5`, effort `medium`, 구조화 출력, 시스템 프롬프트 캐시,
정책상 거절 시 서버 측 자동 대체(`fallbacks: "default"`, 베타 `server-side-fallback-2026-07-01`).

## 1. 로컬에서 먼저 써 보기
```bash
cd functions
npm install
ANTHROPIC_API_KEY=sk-ant-... APP_TOKEN=dev-token npm run dev     # http://localhost:8787/dailyPack

# 다른 터미널에서
flutter run -d chrome \
  --dart-define=CONTENT_API_URL=http://localhost:8787/dailyPack \
  --dart-define=CONTENT_API_TOKEN=dev-token
```
휴대폰 실기기에서는 `localhost` 대신 PC 의 사설 IP(예: `http://192.168.0.10:8787/dailyPack`)를 쓰세요.

## 2. Firebase 에 배포
1. https://console.firebase.google.com 에서 프로젝트 생성 (Blaze 요금제 필요 — 외부 API 호출 때문)
2. `npm i -g firebase-tools && firebase login && firebase use --add` (프로젝트 선택)
3. 비밀 값 저장 (저장소에는 절대 넣지 않음)
   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY   # Claude API 키
   firebase functions:secrets:set APP_TOKEN           # 아무도 모르는 긴 랜덤 문자열 (openssl rand -hex 32)
   ```
4. `cd functions && npm run deploy`
5. 배포 후 나오는 URL 로 앱 빌드
   ```bash
   flutter build apk \
     --dart-define=CONTENT_API_URL=https://asia-northeast3-<프로젝트>.cloudfunctions.net/dailyPack \
     --dart-define=CONTENT_API_TOKEN=<APP_TOKEN 값>
   ```

## 보안 메모
- Claude API 키는 서버(Secret Manager)에만 있고 앱에는 들어가지 않습니다.
- `APP_TOKEN` 은 앱 안에 들어가므로 완벽한 비밀은 아닙니다. 개인용 앱에서 낯선 호출을 막는 용도이며,
  `maxInstances: 2` 로 비용 폭주를 막아 둡니다. 여러 사람이 쓰게 되면 Firebase Auth + App Check 로 바꾸세요.

## 비용 감각
하루 1번(+ 내일 팩 미리 받기) 호출이므로 개인 사용 기준 하루 몇십 원 ~ 몇백 원 수준입니다.
정확한 금액은 Anthropic Console 의 사용량 화면에서 확인하세요.

## 테스트
```bash
cd functions && npm test          # 규칙 검사·재시도·HTTP 처리 (가짜 Claude 클라이언트, 비용 없음)
npm run fixture                   # 서버 JSON 샘플 갱신 → 앱의 계약 테스트(test/domain/pack_source_test.dart)가 사용
```
