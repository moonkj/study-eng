import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:todaye/data/grade_source.dart' show ToeicTaskType;
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/study_log.dart';
import 'package:todaye/domain/toeic_feedback.dart';

import 'daily_flow_test.dart' show app, seeded;

/// 사용자에게 보이는 실력은 토스 등급만: CEFR 표기(A2, B1.2, "CEFR")가 화면에 없어야 한다
final _cefr = RegExp(r'\b(CEFR|[ABC][12](\.[123])?)\b');

/// 화면에 그려진 모든 글자 (RichText 포함)
List<String> _texts(WidgetTester tester) => [
  for (final e in find.byType(RichText).evaluate()) (e.widget as RichText).text.toPlainText(),
];

/// 목록이 한 번에 다 그려지도록 아주 긴 화면
Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void _expectNoCefr(WidgetTester tester, String screen) {
  final found = _texts(tester).where(_cefr.hasMatch).toList();
  expect(found, isEmpty, reason: '$screen 화면에 CEFR 표기가 있어요: $found');
}

MemoryStore _done() {
  final d = seeded();
  return MemoryStore(
    SavedData(
      profile: d.profile,
      contentStep: d.contentStep,
      onboarded: true,
      log: {...d.log, '2026-11-22': const DayRecord(accuracy: 0.9, levelScore: 790, quizCorrect: 11, quizTotal: 12)},
      // 어제 레벨 점수 764 → 790: 내부 레벨이 올라도 화면에는 CEFR 이 나오지 않는다
      today: const TodayProgress(
        date: '2026-11-22',
        done: {'expressions', 'words', 'speaking', 'quiz'},
        levelDelta: 40,
      ),
    ),
  );
}

void main() {
  for (final path in ['/', '/progress', '/settings', '/level-result']) {
    testWidgets('$path: CEFR 표기 없이 토스 등급만', (tester) async {
      await _tall(tester);
      await tester.pumpWidget(app(initial: path));
      await tester.pumpAndSettle();
      _expectNoCefr(tester, path);
      expect(_texts(tester).any((t) => RegExp(r'(NL|NM|NH|IL|IM[123]|IH|AL)').hasMatch(t)), isTrue);
    });
  }

  testWidgets('완료 화면: CEFR 레벨 점수 대신 토스 예상 등급', (tester) async {
    await _tall(tester);
    await tester.pumpWidget(app(initial: '/complete', store: _done()));
    await tester.pumpAndSettle();
    _expectNoCefr(tester, '완료');
    expect(find.text('토스 예상 등급'), findsOneWidget);
    expect(find.text('레벨 점수'), findsNothing);
  });

  testWidgets('완료 화면: 토스 결과가 먼저, 요약은 "토스 말하기 N개" (문장 0개 아님)', (tester) async {
    await _tall(tester);
    final d = seeded();
    await tester.pumpWidget(
      app(
        initial: '/complete',
        store: MemoryStore(
          SavedData(
            profile: d.profile,
            contentStep: d.contentStep,
            onboarded: true,
            log: d.log,
            today: const TodayProgress(
              date: '2026-11-22',
              done: {'expressions', 'words', 'speaking', 'quiz'},
              toeic: {
                'ra': ToeicTaskRecord(type: ToeicTaskType.readAloud, score: 80, graded: true),
                'pic': ToeicTaskRecord(type: ToeicTaskType.picture, score: 70, graded: true),
                'op': ToeicTaskRecord(type: ToeicTaskType.opinion, score: 60, graded: true),
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('오늘 토스 평균 70점'), findsOneWidget);
    expect(find.text('채점 기준 IM3 수준 · 목표 IM3 · 140점'), findsOneWidget);
    expect(find.text('표현 3개 · 단어 10개 · 토스 말하기 3개 완료'), findsOneWidget);
    expect(find.text('토스 평균'), findsOneWidget);
    expect(find.text('IM2~IM3'), findsOneWidget); // 토스 예상 등급 카드 (채점 3회 평균 70 ±5)
    _expectNoCefr(tester, '완료');
  });

  testWidgets('환영 화면·진단 건너뛰기 시트: CEFR 표기 없음', (tester) async {
    await _tall(tester);
    await tester.pumpWidget(app(store: MemoryStore()));
    await tester.pumpAndSettle();
    _expectNoCefr(tester, '환영');
    await tester.tap(find.text('진단 없이 바로 시작'));
    await tester.pumpAndSettle();
    _expectNoCefr(tester, '진단 건너뛰기');
  });

  testWidgets('레벨 진단 중에도 문제 난이도는 토스 등급으로', (tester) async {
    await _tall(tester);
    await tester.pumpWidget(app(initial: '/level-test'));
    await tester.pumpAndSettle();
    _expectNoCefr(tester, '레벨 진단');
  });

  testWidgets('홈: Claude 채점 모의고사가 있으면 채점 기준 등급 범위를 보여 준다', (tester) async {
    await _tall(tester);
    final d = seeded();
    await tester.pumpWidget(
      app(
        store: MemoryStore(
          SavedData(
            profile: d.profile,
            contentStep: d.contentStep,
            onboarded: true,
            log: d.log,
            mocks: const [
              MockResult(date: '2026-11-21', level: 'IM3', target: 'IM3', scores: [72], graded: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('지금 IM2~IM3'), findsOneWidget);
    expect(find.text('최근 채점 1회 기준'), findsOneWidget);
    _expectNoCefr(tester, '홈');
  });
}
