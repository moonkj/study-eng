import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/domain/daily_adjuster.dart';
import 'package:todaye/domain/level.dart';

const profile = LearnerProfile(
  overall: Level(764),
  skills: {
    Skill.vocabulary: Level(980),
    Skill.grammar: Level(720),
    Skill.listening: Level(700),
    Skill.speaking: Level(430),
  },
);

DailyResult result({int correct = 8, double? speaking = 80, int wordsKnown = 6, int expKnown = 0}) => DailyResult(
  quizCorrect: correct,
  quizTotal: 10,
  wordsKnown: wordsKnown,
  wordsTotal: 10,
  speakingAverage: speaking,
  expressionsAlreadyKnown: expKnown,
  expressionsTotal: 3,
);

void main() {
  test('이틀 연속 정답률 85% 초과면 난이도를 한 단계 올린다', () {
    final adj = DailyAdjuster.adjust(
      profile: profile,
      currentContentStep: 7,
      today: result(correct: 9),
      yesterdayAccuracy: 0.88,
    );
    expect(adj.nextContentStep, 8);
    expect(adj.reasons.first, contains('정답률 90%'));
  });

  test('어제 정답률이 낮았으면 하루 높았다고 바로 올리지 않는다', () {
    final adj = DailyAdjuster.adjust(
      profile: profile,
      currentContentStep: 7,
      today: result(correct: 9),
      yesterdayAccuracy: 0.7,
    );
    expect(adj.nextContentStep, 7);
  });

  test('정답률 65% 미만이면 한 단계 낮춘다', () {
    final adj = DailyAdjuster.adjust(profile: profile, currentContentStep: 7, today: result(correct: 5));
    expect(adj.nextContentStep, 6);
    expect(adj.levelDelta, lessThan(0));
  });

  test('목표 구간(65~85%)이면 난이도를 유지한다', () {
    final adj = DailyAdjuster.adjust(profile: profile, currentContentStep: 7, today: result(correct: 8));
    expect(adj.nextContentStep, 7);
  });

  test('이미 아는 표현이 많으면 한 단계 올린다', () {
    final adj = DailyAdjuster.adjust(profile: profile, currentContentStep: 7, today: result(correct: 8, expKnown: 2));
    expect(adj.nextContentStep, 8);
  });

  test('난이도는 내 레벨 -1 ~ +2 단계 안에서만 움직인다', () {
    final adj = DailyAdjuster.adjust(
      profile: profile,
      currentContentStep: 9,
      today: result(correct: 10),
      yesterdayAccuracy: 0.95,
    );
    expect(adj.nextContentStep, 9); // 레벨 B1.2(7) + 2 = 9 상한
  });

  test('약한 말하기 영역은 다음 날 문장 수를 늘린다', () {
    final adj = DailyAdjuster.adjust(profile: profile, currentContentStep: 7, today: result());
    expect(adj.focusSkill, Skill.speaking);
    expect(adj.speakingSentences, 12);
  });

  test('말하기 점수가 높으면 말하기 영역 점수가 오른다', () {
    final adj = DailyAdjuster.adjust(profile: profile, currentContentStep: 7, today: result(speaking: 95));
    expect(adj.profile.skills[Skill.speaking]!.score, greaterThan(profile.skills[Skill.speaking]!.score));
  });
}
