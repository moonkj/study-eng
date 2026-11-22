# todaye(오늘의 영어) — 상세 개발 계획

> 책 없이 폰 하나로. AI 영어 선생님이 매일 **회화 표현 3개 → 단어 10개 → 실생활 예문 → 복습 퀴즈**를 챙겨주고, 출퇴근길에 소리 내어 말하며 외우는 앱.

---

## 1. 배경과 문제 정의

레퍼런스(인스타그램 "Chat GPT 영어선생님" 루틴)에서 사람들이 ChatGPT에 매일 직접 하고 있는 것:

| 단계 | 사용자가 ChatGPT에 하는 요청 | 불편한 점 |
|---|---|---|
| 1 | "오늘의 영어회화 3가지 표현과 예시 2개 줘" | 매일 같은 프롬프트를 직접 입력해야 함 |
| 2 | "단어에 대한 예시까지 꼼꼼하게 알려줘" | 결과 형식이 매번 달라 보기 불편 |
| 3 | "마지막에 테스트지까지 만들어줘" | 채점·오답 관리가 안 됨 |
| 4 | "오늘의 단어 10개 뽑아줘(뜻·발음)" | 지난 단어 복습(망각 곡선) 불가 |
| 5 | 출퇴근하며 보고 중간중간 소리 내어 말하기 | 발음 확인·기록이 안 됨 |

**todaye는 이 루틴을 자동화·구조화하고, ChatGPT 대화창으로는 안 되는 '복습·기록·말하기 피드백'을 더한다.**

### 타깃 사용자
- 20~40대 직장인/대학생, 문법보다 **회화 위주**로 매일 10~15분 공부하고 싶은 사람
- 출퇴근 시간(대중교통)에 한 손으로 학습

### 핵심 가치
1. **매일 자동으로** 준비되는 오늘의 학습 (프롬프트 입력 불필요)
2. **일정한 카드 형식** (표현 / 단어 표 / 예문 / 퀴즈)
3. **입으로 말하기** — TTS로 듣고, 따라 말하면 AI가 피드백
4. **알아서 테스트·복습** — 퀴즈 자동 채점, 틀린 것·지난 단어 간격 반복(SRS)

---

## 2. 팀 에이전트 구성

`.claude/agents/`에 정의되어 있으며, Claude Code에서 `@에이전트이름` 또는 자동 위임으로 호출합니다.

| 에이전트 | 역할 | 주요 산출물 |
|---|---|---|
| `product-planner` | 기획(PM): 유저 스토리, 수용 기준, 우선순위, 마일스톤 | `docs/PLAN.md`, 백로그 |
| `learning-content-expert` | 영어교육 전문가: 커리큘럼, 콘텐츠 품질 기준, 생성 결과 검수 | `docs/content-guidelines.md` |
| `ux-designer` | 화면 흐름, 디자인 시스템, 마이크로카피, 접근성 | `docs/design/*` |
| `flutter-architect` | 구조·상태관리·패키지·ADR·구조 리뷰 | `docs/adr/*`, 앱 골격 |
| `flutter-developer` | 화면/기능 구현 + 테스트 | `lib/**`, `test/**` |
| `ai-backend-engineer` | Cloud Functions + Claude API, 프롬프트, 비용, 보안 | `functions/**` |
| `qa-engineer` | 테스트 케이스, 엣지 케이스 검증, 최종 리뷰 | `docs/qa/*`, 테스트 |

### 협업 흐름 (기능 1개 기준)
```
product-planner ─ 유저스토리/수용기준
      │
      ├─▶ learning-content-expert ─ 콘텐츠 형식·품질 기준 ─┐
      ├─▶ ux-designer ─ 화면 스펙·토큰 ───────────────────┤
      │                                                    ▼
      └─▶ flutter-architect ─ 구조/ADR ─▶ flutter-developer ◀─▶ ai-backend-engineer
                                                    │
                                                    ▼
                                              qa-engineer ─ 리뷰/테스트 ─▶ 머지
```

---

## 3. 기능 명세

### 3.1 MVP (Must)

| # | 기능 | 설명 | 레퍼런스 대응 |
|---|---|---|---|
| F1 | 온보딩·레벨 설정 | 목표(회화/여행/비즈니스), 레벨 자가진단(간단 5문항), 알림 시간 | — |
| F2 | 오늘의 영어회화 3가지 | 표현 패턴 + 뜻 + 언제 쓰는지 + 예문 2개(번역) + TTS | 5/10 |
| F3 | 오늘의 단어 10개 | 단어 / 뜻 / 한글 발음 / IPA / 예문, 표 형태 + 카드 넘기기 | 7/10 |
| F4 | 실생활 예문 10개 | 오늘 단어를 사용한 구어체 문장 + 번역, 문장별 듣기 | 8/10 |
| F5 | 소리 내어 말하기 | 문장을 듣고 따라 말하기 → STT 인식 → 일치도 표시 | 8/10 "입으로 말하며" |
| F6 | 오늘의 복습 퀴즈 | 한→영 4지선다, 빈칸 채우기 / 자동 채점 / 정답 해설 | 6/10 |
| F7 | 오답·단어장 + SRS 복습 | 틀린 문제·학습 단어를 간격 반복(1·3·7·14·30일)으로 다시 출제 | "알아서 테스트까지" |
| F8 | 학습 기록·Streak | 연속 학습일, 일일 루틴 완료율, 캘린더 | — |
| F9 | 아침 알림 | 설정 시각(예: 07:30)에 "오늘의 표현이 도착했어요" 푸시 | 출근 준비 시간 |
| F10 | 오프라인 캐시 | 오늘 팩을 받아두면 지하철에서도 학습 가능 | 출퇴근 |

### 3.2 2차 (Should)
- F11 **AI 선생님 채팅**: 오늘 표현으로 롤플레이(카페 주문, 회의 등), 문장 교정
- F12 **말하기 AI 피드백**: 단순 일치도 → "더 자연스러운 표현" 제안
- F13 **홈 화면/잠금화면 위젯**: 오늘의 표현 1개 노출 (iOS WidgetKit, Android Glance)
- F14 **주제 선택**: 오늘은 "회사", 내일은 "여행" 식으로 직접 고르기
- F15 **듣기 모드**: 이어폰으로 오늘 표현·예문 연속 재생(화면 꺼도)

### 3.3 3차 (Could)
- 친구와 streak 경쟁, 공유 카드 이미지(인스타 스토리용)
- 주간 리포트, 레벨 업 테스트
- 구독 결제(무료: 일일 팩 / 유료: AI 채팅·말하기 피드백 무제한)

### 3.4 하지 않을 것 (Won't, MVP 기준)
- 문법 강의 콘텐츠, 장문 독해, 원어민 1:1 매칭

---

## 4. 하루 학습 루프 (UX 플로우)

```
[아침 알림 07:30] ─▶ 홈(오늘 진행률 0/4)
                       │
   ① 오늘의 표현 3개 (3분) ─ 듣기 ▶ 따라 말하기
   ② 오늘의 단어 10개 (4분) ─ 카드 넘기기, 아는 단어 체크
   ③ 실생활 예문 10개 (4분) ─ 문장별 듣기·말하기
   ④ 복습 퀴즈 (3분) ─ 오늘 내용 + SRS 복습 문제 섞어서 출제
                       │
                 [완료 화면] streak +1, 틀린 문제 → 오답노트
```

### 화면 목록 (MVP)
1. 스플래시 / 온보딩(3단계) / 로그인(익명 → 선택적으로 Apple·Google 연동)
2. **홈**: 오늘 날짜, 진행률 링, 4개 단계 카드, streak
3. 오늘의 표현 상세 (카드 3장 스와이프)
4. 오늘의 단어 (표 보기 ↔ 플래시카드 보기 토글)
5. 실생활 예문 (리스트 + 문장별 🔊/🎤)
6. 말하기 바텀시트 (녹음 → 인식 결과 → 일치 하이라이트)
7. 퀴즈 (문항 → 정답/해설 → 결과 요약)
8. 복습 탭 (오늘 복습할 카드 N개, 오답노트, 단어장 검색)
9. 기록 탭 (캘린더, 통계)
10. 설정 (레벨, 알림 시간, TTS 속도/음성(미국/영국), 다크모드)

하단 탭: **오늘 · 복습 · 기록 · 설정** (2차에 'AI 선생님' 탭 추가)

---

## 5. 기술 아키텍처

```
┌──────────── Flutter App (iOS/Android) ────────────┐
│ presentation (Riverpod) ─ domain ─ data            │
│   ├ Drift(SQLite): 오늘 팩 캐시, 학습기록, SRS     │
│   ├ flutter_tts / speech_to_text                   │
│   └ Firebase SDK (Auth, Firestore, FCM, Analytics) │
└───────────────┬───────────────────────────────────┘
                │ HTTPS (Firebase Auth + App Check)
┌───────────────▼──────── Firebase ─────────────────┐
│ Firestore: daily_packs, users, progress            │
│ Cloud Functions (TypeScript):                      │
│   ├ scheduled: generateDailyPacks (매일 03:00 KST) │
│   ├ callable: getTodayPack                         │
│   ├ callable: tutorChat (스트리밍, 2차)           │
│   └ callable: speakingFeedback (2차)              │
│ Secret Manager: ANTHROPIC_API_KEY                  │
└───────────────┬───────────────────────────────────┘
                ▼
         Claude API (@anthropic-ai/sdk)
```

### 5.1 기술 스택
| 영역 | 선택 | 이유 |
|---|---|---|
| 앱 | Flutter (이미 프로젝트 생성됨), Material 3 | iOS/Android 동시 |
| 상태관리 | Riverpod + riverpod_generator | 테스트 용이, 비동기 처리 |
| 라우팅 | go_router | 딥링크(알림 → 오늘 화면) |
| 모델 | freezed + json_serializable | 불변 모델, JSON 직렬화 |
| 로컬 DB | Drift | SRS 쿼리, 오프라인 |
| 음성 | flutter_tts, speech_to_text | 기기 내장 엔진(무료) |
| 백엔드 | Firebase (Auth/Firestore/Functions/FCM/Remote Config/Crashlytics) | 서버 운영 부담 최소 |
| AI | Claude API, 공식 TypeScript SDK | 구조화 출력·배치·캐싱 |

### 5.2 AI 콘텐츠 생성 전략 (비용 핵심)
1. **사용자별 생성 X, 레벨별 공유 팩 O**: 매일 새벽 레벨(4단계) × 1팩만 생성 → 사용자 수와 무관하게 하루 4회 호출 수준.
2. **Message Batches API**로 생성 → 일반 호출 대비 50% 비용. 실시간성이 필요 없으므로 적합.
3. **구조화 출력(`output_config.format`)** 으로 JSON 스키마 강제 → 앱이 항상 같은 카드 형식으로 렌더링.
4. **검증 단계**: 서버에서 스키마 재검증 + 규칙 검사(단어 10개인지, 예문에 오늘 단어가 들어갔는지, 퀴즈 정답이 보기 안에 있는지, 최근 30일과 중복 표현 없는지). 실패 시 재생성, 그래도 실패하면 사전 검수된 예비 팩 사용.
5. 모델: 기본 `claude-opus-5-5`. 배치는 비실시간이므로 품질 우선. 비용 절감용 모델 변경은 실제 비용 데이터를 본 뒤 결정.
6. **2차 실시간 기능**(채팅·말하기 피드백)은 시스템 프롬프트 고정 → prompt caching, 사용자당 일일 한도, 스트리밍 응답.

### 5.3 데이터 모델 (요약)

```jsonc
// Firestore: daily_packs/{yyyy-MM-dd}_{level}
{
  "date": "2026-11-23", "level": "A2", "topic": "출근길",
  "expressions": [            // 3개
    { "pattern": "I've been meaning to ~", "meaning": "계속 ~하려고 했어",
      "usage": "오래전부터 하고 싶었지만 아직 못 한 일을 말할 때",
      "examples": [{ "en": "I've been meaning to read this book.", "ko": "이 책을 계속 읽으려고 했어." }] }
  ],
  "words": [                  // 10개
    { "word": "actually", "pos": "adv", "meaning": "사실은, 실제로",
      "pronKo": "액츄얼리", "ipa": "ˈæktʃuəli",
      "example": { "en": "Actually, I'm a little tired.", "ko": "사실 나 조금 피곤해." } }
  ],
  "sentences": [ { "en": "...", "ko": "...", "wordRefs": ["actually"] } ],   // 10개
  "quiz": [                   // 5~8문항
    { "type": "ko_to_en_choice", "prompt": "너한테 계속 전화하려고 했어.",
      "choices": ["I'm in the mood for calling you.", "I've been meaning to call you.", "I'm trying to call you."],
      "answerIndex": 1, "explanation": "I've been meaning to는 '이전부터 하려고 생각해 왔다'는 의미야." }
  ],
  "version": 1, "model": "…", "createdAt": "…"
}
```

```text
// Drift (로컬)
study_items(id, type[expression|word|sentence], payload_json, first_seen_date)
srs_cards(item_id, ease, interval_days, due_date, lapses)
quiz_attempts(id, item_id, correct, answered_at)
daily_progress(date, steps_done_bitmask, completed_at)
speaking_attempts(id, item_id, recognized_text, score, at)
```

### 5.4 SRS 규칙 (MVP 단순화 버전)
- 처음 학습 → 1일 후 → 3일 → 7일 → 14일 → 30일 → 졸업
- 퀴즈에서 틀리면 간격을 1일로 리셋, 맞으면 다음 단계
- 매일 퀴즈 = 오늘 신규 문항 + due 카드 최대 5개

### 5.5 보안·개인정보
- LLM API 키는 Secret Manager에만. 앱 번들/깃 저장소 금지.
- Functions는 Firebase Auth + App Check 필수, 사용자별 rate limit.
- 음성은 기기 내 STT로 처리하고 서버에는 인식된 텍스트만 전송(2차 피드백 시).
- 개인정보처리방침, 마이크 권한 사유 문구(iOS `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).

---

## 6. 마일스톤 (1인 + 에이전트 팀 기준, 약 10주)

| 단계 | 기간 | 목표 | 주 담당 에이전트 | 완료 기준 |
|---|---|---|---|---|
| **M0 준비** | 1주 | 기획 확정, 콘텐츠 가이드, 디자인 시스템, ADR | planner, content, ux, architect | 문서 4종 리뷰 완료 |
| **M1 앱 골격** | 1주 | 패키지·폴더 구조, 테마, 라우터, 하단 탭, Drift 스키마, 기존 카운터 코드 제거 | architect, developer | 빈 탭 앱 실행, CI(analyze+test) 통과 |
| **M2 오늘의 학습(목업 데이터)** | 2주 | F2·F3·F4 화면 + TTS, 로컬 JSON 목업 팩으로 동작 | developer, ux | 목업 팩으로 ①②③ 단계 완주 |
| **M3 AI 콘텐츠 파이프라인** | 2주 | Functions + Claude 배치 생성 + 검증 + Firestore, 앱 연동·오프라인 캐시(F10) | ai-backend, content | 3일 연속 자동 생성, 검수 통과율 ≥ 95% |
| **M4 퀴즈·복습·말하기** | 2주 | F5·F6·F7·F8 | developer, qa | SRS 로직 unit test 100%, 핵심 루프 integration test |
| **M5 온보딩·알림·출시 준비** | 1주 | F1·F9, Crashlytics/Analytics, 아이콘·스토어 자료 | developer, ux, planner | TestFlight / 내부 테스트 트랙 배포 |
| **M6 베타 & 개선** | 1주 | 지인 베타 10~20명, 지표 확인, 버그 수정 | qa, planner | D7 리텐션·루틴 완료율 측정 |
| 이후 | — | 2차 기능(F11~F15) | — | — |

### M1 상세 작업 (바로 시작 가능)
1. `pubspec.yaml` 정리: 앱 이름/설명, 패키지 추가 (riverpod, go_router, freezed, drift, flutter_tts 등)
2. Android 패키지명 정리 — 현재 `com.example.todaye`와 `com.todaye` 두 MainActivity가 공존 → 하나로 통일
3. `lib/` feature-first 구조 생성, `main.dart` 카운터 데모 제거
4. 디자인 토큰 → `lib/core/theme/` (라이트/다크)
5. 하단 탭 4개 + go_router
6. Drift 스키마 + 마이그레이션 테스트
7. GitHub Actions: `flutter analyze`, `flutter test`

---

## 7. 성공 지표
| 지표 | 목표(베타) |
|---|---|
| 일일 루틴 완료율(4단계 모두) | ≥ 50% |
| D7 리텐션 | ≥ 30% |
| 평균 학습 시간 | 10~15분 |
| 퀴즈 정답률 | 70~85% (너무 높으면 난이도↑) |
| 콘텐츠 신고율(오류·어색함) | < 1% |

---

## 8. 리스크와 대응
| 리스크 | 대응 |
|---|---|
| AI가 어색하거나 틀린 영어 생성 | 구조화 출력 + 규칙 검증 + 신고 버튼 + 초기엔 content-expert가 샘플 수동 검수 |
| API 비용 증가 | 공유 팩 + 배치(50%), 실시간 기능은 한도·캐싱, 일별 비용 로그 |
| STT 정확도(한국인 발음) | 엄격한 일치 대신 핵심 단어 포함 여부로 관대하게 채점, 2차에 AI 피드백 |
| 생성 실패/장애 | 예비 팩(사전 검수된 30일치) 폴백 |
| 학습 지속성 낮음 | 아침 알림, streak, 10분 이내 분량, 위젯(2차) |

---

## 9. 확정된 방향 (2026-11-22)
- **개인용 앱**: 수익 모델·소셜 로그인·스토어 마케팅은 범위에서 제외. 공유 팩 대신 **나만을 위한 맞춤 팩**을 매일 생성.
- **Claude API 사용**: 콘텐츠 생성, 말하기 피드백, AI 선생님에 사용.
- **최우선 가치**: 계속 공부하고 싶어지는 유려한 UX/UI + 내 레벨에 맞춘 학습 시스템.
  - 디자인 시스템: `docs/design/design-system.md`
  - 레벨 시스템: `docs/level-system.md`
  - 화면 시안(Claude Design): https://claude.ai/artifact/G2JJ6akobFwcDJM7MwvheE
- 레퍼런스 스크린샷은 참고용이며 그대로 따르지 않음.
