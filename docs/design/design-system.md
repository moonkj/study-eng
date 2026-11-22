# todaye 디자인 시스템 — "따뜻한 종이 노트"

화면 시안: https://claude.ai/artifact/G2JJ6akobFwcDJM7MwvheE (Claude Design 캔버스, 9개 화면)

## 원칙
- 한 화면에 한 가지 일만. 주요 버튼은 엄지가 닿는 하단에.
- 영어 = 세리프(Newsreader), 한글 = 산세리프(IBM Plex Sans KR)로 역할을 구분.
- 형광펜 밑줄 = "오늘 외울 부분".
- 틀렸을 때도 실패 표현 없이 구체적으로 안내("아깝다! 비슷한 표현이랑 헷갈렸어요").

## 색 토큰 (라이트)
| 토큰 | 값 | 용도 |
|---|---|---|
| paper | #F5F0E6 | 배경 |
| card | #FFFDF8 | 카드 |
| line | #E4DCCB | 테두리·구분선 |
| sand | #E9E1D1 | 보조 면(레벨 카드, 팁) |
| ink | #1F1D1A | 본문, 주요 버튼 |
| ink-2 | #5F584D | 보조 텍스트 (paper 대비 약 6:1) |
| pen-blue | #2C4A7A | 포인트, 레벨, 듣기 버튼 |
| pen-blue-tint | #EAEFF6 | 선택 상태, AI 안내 박스 |
| highlighter | #F3DB7A | 형광펜, 어두운 버튼 위 강조 |
| success | #3F6B4A / tint #EEF3EC | 정답 |
| error | #A8432F / tint #F8ECE7 | 오답, 약점 |
| ember | #B4532A | streak 불꽃, 보강 필요 영역 |

다크 모드는 Flutter 구현 단계에서 paper → #17150F, card → #211E18, ink ↔ 반전 기준으로 정의.

## 타이포
| 스타일 | 폰트 | 크기/굵기 |
|---|---|---|
| 영어 표현 대제목 | Newsreader | 36 / 500 |
| 영어 단어 | Newsreader | 52 / 500 |
| 영어 예문 | Newsreader | 17–18 / 400 |
| 화면 제목 | IBM Plex Sans KR | 24–26 / 700 |
| 본문 | IBM Plex Sans KR | 14–15 / 400–600 |
| 캡션 | IBM Plex Sans KR | 12–13 / 400–600 |

## 형태
- 반경: 카드 20–28, 버튼 16, 칩 12–13, 원형 아이콘 버튼 44
- 간격: 4의 배수 (8 / 12 / 16 / 20 / 24)
- 주요 버튼 높이 56, 최소 터치 영역 44
- 그림자: 카드 `0 18px 30px -22px rgba(60,45,20,.35)` 정도로 아주 옅게

## 화면 목록
홈 · 레벨 진단 · 레벨 결과 · 기록 · ①표현 · ②단어 · ③말하기 · ④퀴즈 · 완료
