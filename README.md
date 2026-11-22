# todaye — 오늘의 영어

내 레벨에 맞춰 매일 **표현 3개 → 단어 10개 → 따라 말하기 → 복습 퀴즈**를 챙겨주는 개인용 영어 학습 앱 (Flutter).

- 디자인: A안 "따뜻한 종이 노트" — `docs/design/design-system.md`, [Claude Design 캔버스](https://claude.ai/artifact/G2JJ6akobFwcDJM7MwvheE)
- 레벨 시스템: `docs/level-system.md`
- 전체 계획: `docs/PLAN.md`

## 실행

```bash
flutter pub get
flutter run            # 기기/에뮬레이터
flutter run -d chrome  # 웹으로 빠르게 확인
flutter test           # 레벨 엔진·SRS·채점 단위 테스트 + 하루 루틴 위젯 테스트
```

Flutter 3.50 이상 (Material은 `package:material_ui` 사용).

## 구조

```
lib/
  app/        앱, 라우터(go_router), 학습 상태(Riverpod)
  core/       디자인 토큰, 테마, 공용 위젯
  domain/     레벨·적응형 진단·일일 난이도 조정·SRS·말하기 채점 (순수 Dart, 테스트 대상)
  data/       모델, 샘플 콘텐츠
  features/   home, expression, words, speaking, quiz, complete,
              level_test, level_result, progress, review, settings
```
