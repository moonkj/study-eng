import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/data/toeic.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/toeic_feedback.dart';
import 'package:todaye/domain/toeic_level.dart';
import 'package:todaye/domain/toeic_weakness.dart' show ToeicDayScore;

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
      final e = estimateToeic(mocks: const [], toeicLog: const {}, levelStep: 7);
      expect(e.approximate, isTrue);
      expect(e.label, 'IM3 · 140점');
      expect(e.display, '예상 IM3 · 140점');
      expect(e.previous, isNull);
    });

    test('기기 점수만 본 모의고사·채점 여부를 모르는 예전 루틴 기록은 등급에 쓰지 않는다', () {
      final e = estimateToeic(
        mocks: const [
          MockResult(date: '2026-11-20', level: 'AL', target: 'IM3', scores: [95]),
        ],
        toeicLog: const {
          '2026-11-21': {'picture': ToeicDayScore(best: 95)},
        },
        levelStep: 6,
      );
      expect(e.approximate, isTrue);
      expect(e.level, 'IM2');
    });

    test('모의고사 등급 범위(가중 원점수 추정)를 그대로 쓴다', () {
      final e = estimateToeic(
        mocks: const [
          MockResult(date: '2026-11-10', level: 'IM1~IM2', target: 'IM3', graded: true),
          MockResult(date: '2026-11-20', level: 'IM2~IM3', target: 'IM3', graded: true),
        ],
        toeicLog: const {},
        levelStep: 3,
      );
      expect(e.approximate, isFalse);
      expect(e.label, 'IM2~IM3');
      expect(e.display, 'IM2~IM3');
      expect(e.previous, 'IM2'); // 지난 모의고사 범위의 위쪽
      expect(e.basis, '11월 20일 모의고사 채점 기준');
    });

    test('모의고사 뒤 루틴 첫 시도가 3개 미만이면 모의고사 범위, 3개 이상이면 루틴 기록', () {
      const mock = MockResult(date: '2026-11-20', level: 'IM3', target: 'IM3', graded: true);
      final few = estimateToeic(
        mocks: const [mock],
        toeicLog: const {
          '2026-11-19': {'picture': ToeicDayScore(first: 40, best: 40)}, // 모의고사 전 기록은 세지 않는다
          '2026-11-21': {'picture': ToeicDayScore(first: 50, best: 90)},
          '2026-11-22': {'opinion': ToeicDayScore(first: 50, best: 50)},
        },
        levelStep: 0,
      );
      expect(few.label, 'IM3 · 140점');
      expect(few.mockDate, '2026-11-20');

      final many = estimateToeic(
        mocks: const [mock],
        toeicLog: const {
          '2026-11-21': {'picture': ToeicDayScore(first: 50, best: 90)},
          '2026-11-22': {
            'opinion': ToeicDayScore(first: 50, best: 50),
            'read_aloud': ToeicDayScore(first: 75, best: 75),
          },
        },
        levelStep: 0,
      );
      // 첫 시도만: 50, 50, 75 → 평균 58.3 → 53.3(IL) ~ 63.3(IM2) (다시 해서 오른 90은 쓰지 않는다)
      expect(many.mockDate, isNull);
      expect(many.samples, 3);
      expect(many.label, 'IL~IM2');
      expect(many.basis, '최근 채점 3회 기준 (그날 첫 시도)');
    });

    test('모의고사가 없으면 루틴 첫 시도 평균 ±5점, 경계에 걸치면 범위로', () {
      final e = estimateToeic(
        mocks: const [],
        toeicLog: const {
          '2026-11-20': {'picture': ToeicDayScore(first: 72, best: 72)},
        },
        levelStep: 3,
      );
      expect(e.approximate, isFalse);
      expect(e.samples, 1);
      expect(e.label, 'IM2~IM3'); // 72 → 67(IM2) ~ 77(IM3)
    });

    test('최근 5개만 보고, 지난번 등급은 가장 최근 기록을 빼고 본 값', () {
      final e = estimateToeic(
        mocks: const [],
        toeicLog: {
          for (var i = 0; i < 3; i++) '2026-11-0$i': const {'picture': ToeicDayScore(first: 0, best: 0)},
          for (var i = 0; i < 5; i++) '2026-11-1$i': const {'picture': ToeicDayScore(first: 100, best: 100)},
        },
        levelStep: 0,
      );
      expect(e.samples, 5);
      expect(e.label, 'AL · 180점');
      expect(e.previous, 'AL');
    });
  });
}
