import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/data/grade_source.dart' show ToeicTaskType;
import 'package:todaye/data/toeic.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/toeic_feedback.dart';
import 'package:todaye/domain/toeic_level.dart';

void main() {
  group('CEFR → 토스 어림 등급', () {
    test('15단계 전체 표', () {
      final table = {
        for (var step = 0; step < Level.stepCount; step++) Level.fromStep(step).label: toeicLevelForStep(step),
      };
      expect(table, {
        'A1.1': 'NL',
        'A1.2': 'NM',
        'A1.3': 'NH',
        'A2.1': 'IL',
        'A2.2': 'IL',
        'A2.3': 'IM1',
        'B1.1': 'IM2',
        'B1.2': 'IM3',
        'B1.3': 'IM3',
        'B2.1': 'IH',
        'B2.2': 'IH',
        'B2.3': 'AL',
        'C1.1': 'AL',
        'C1.2': 'AL',
        'C1.3': 'AL',
      });
    });

    test('목표 등급의 표현 난이도 단계를 바꾸면 그 목표 등급이 나온다 (두 표가 어긋나지 않게)', () {
      for (final t in ToeicTarget.values) {
        expect(toeicLevelForStep(t.contentStep), t.label, reason: t.name);
      }
    });

    test('등급이 낮은 단계에서 높은 단계로 줄지 않는다', () {
      for (var step = 1; step < Level.stepCount; step++) {
        expect(
          toeicLevelIndex(toeicLevelForStep(step)),
          greaterThanOrEqualTo(toeicLevelIndex(toeicLevelForStep(step - 1))),
        );
      }
    });

    test('범위 밖 단계도 안전하게', () {
      expect(toeicLevelForStep(-3), 'NL');
      expect(toeicLevelForStep(99), 'AL');
    });
  });

  test('등급 라벨은 "IM3 · 140점" (목표 점수와 같은 대표 점수)', () {
    expect(toeicLevelLabel('IM3'), 'IM3 · 140점');
    expect(toeicLevelLabel('NL'), 'NL · 30점');
    for (final t in ToeicTarget.values) {
      expect(toeicLevelScore[t.label], t.score);
    }
    expect(toeicLevelScore.keys.toList(), toeicLevels);
  });

  test('표현 난이도는 목표와 견준 쉬운 말로', () {
    expect(difficultyKo(7, 7), '목표 수준');
    expect(difficultyKo(8, 7), '조금 어렵게');
    expect(difficultyKo(6, 7), '조금 쉽게');
    expect(difficultyKo(10, 7), '어렵게');
    expect(difficultyKo(3, 7), '쉽게');
    for (var d = 0; d < Level.stepCount; d++) {
      expect(difficultyKo(d, 7), isNot(matches(RegExp(r'[ABC][12]'))));
    }
  });

  group('예상 등급', () {
    test('채점 기록이 없으면 진단(CEFR)을 어림한 "예상" 등급', () {
      final e = estimateToeic(mocks: const [], today: const [], levelStep: 7);
      expect(e.approximate, isTrue);
      expect(e.label, 'IM3 · 140점');
      expect(e.display, '예상 IM3 · 140점');
      expect(e.previous, isNull);
    });

    test('기기 점수(채점 아님)만 있으면 등급을 내지 않고 어림값 그대로', () {
      final e = estimateToeic(
        mocks: const [
          MockResult(date: '2026-11-20', level: 'AL', target: 'IM3', scores: [95]),
        ],
        today: const [ToeicTaskRecord(type: ToeicTaskType.picture, score: 95)],
        levelStep: 6,
      );
      expect(e.approximate, isTrue);
      expect(e.level, 'IM2');
    });

    test('Claude 채점 평균 ±5점이 등급 경계에 걸치면 범위로', () {
      final e = estimateToeic(
        mocks: const [
          MockResult(date: '2026-11-20', level: 'IM3', target: 'IM3', scores: [72], graded: true),
        ],
        today: const [],
        levelStep: 3,
      );
      expect(e.approximate, isFalse);
      expect(e.samples, 1);
      expect(e.label, 'IM2~IM3'); // 72 → 67(IM2) ~ 77(IM3)
      expect(e.display, 'IM2~IM3');
    });

    test('경계에서 멀면 한 등급, 지난번 등급은 가장 최근 기록을 빼고 본 값', () {
      final e = estimateToeic(
        mocks: const [
          MockResult(date: '2026-11-10', level: 'IL', target: 'IM3', scores: [50], graded: true),
          MockResult(date: '2026-11-20', level: 'IM3', target: 'IM3', scores: [50], graded: true),
        ],
        today: const [ToeicTaskRecord(type: ToeicTaskType.opinion, score: 75, graded: true)],
        levelStep: 0,
      );
      // 최근 것부터 75, 50, 50 → 평균 58.3 → 53.3(IL) ~ 63.3(IM2)
      expect(e.samples, 3);
      expect(e.label, 'IL~IM2');
      expect(e.previous, 'IL'); // 50, 50
    });

    test('최근 5개만 본다', () {
      final e = estimateToeic(
        mocks: [
          for (var i = 0; i < 3; i++)
            MockResult(date: '2026-11-0$i', level: 'NL', target: 'IM3', scores: const [0], graded: true),
          for (var i = 0; i < 5; i++)
            MockResult(date: '2026-11-1$i', level: 'AL', target: 'IM3', scores: const [100], graded: true),
        ],
        today: const [],
        levelStep: 0,
      );
      expect(e.samples, 5);
      expect(e.label, 'AL · 180점');
    });
  });
}
