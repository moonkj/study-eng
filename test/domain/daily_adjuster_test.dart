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
  test('오늘 배운 것만 물은 날은 92% 초과가 이틀 이어져야 난이도를 올린다 (직후 재인이라 원래 높게 나옴)', () {
    var adj = DailyAdjuster.adjust(
      profile: profile,
      currentContentStep: 7,
      today: result(correct: 10),
      yesterdayAccuracy: 0.95,
    );
    expect(adj.nextContentStep, 8);
    expect(adj.reasons.first, contains('정답률 100%'));
    // 90% 는 직후 재인 기준으로는 목표 구간 안: 그대로
    adj = DailyAdjuster.adjust(
      profile: profile,
      currentContentStep: 7,
      today: result(correct: 9),
      yesterdayAccuracy: 0.95,
    );
    expect(adj.nextContentStep, 7);
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
    // 어려운 콘텐츠(9)를 다 맞혀 레벨이 오르면 상한도 새 레벨 + 2 로 함께 오른다
    expect(adj.nextContentStep, adj.profile.overall.step + 2);
  });

  test('Elo: 내 레벨보다 쉬운 것을 다 맞히면 조금, 어려운 것을 맞히면 많이 오르고, 쉬운 것을 틀리면 내려간다', () {
    int d(int content, int correct) => eloLevelDelta(
      learnerScore: 764,
      contentScore: content,
      newCorrect: correct,
      newTotal: 10,
      reviewCorrect: 0,
      reviewTotal: 0,
    );
    expect(d(450, 10), inInclusiveRange(0, 3));
    expect(d(950, 10), greaterThan(20));
    expect(d(450, 5), lessThan(-15));
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

  test('난이도는 오늘 배운 것 정답률로, 레벨은 복습 정답률을 더 크게 본다', () {
    // 오늘 배운 것 6/6, 복습 1/4 → 오늘 것만 보면 쉬워 보이지만 기억은 약하다
    const r = DailyResult(
      quizCorrect: 7,
      quizTotal: 10,
      reviewCorrect: 1,
      reviewTotal: 4,
      wordsKnown: 6,
      wordsTotal: 10,
      speakingAverage: 80,
      expressionsAlreadyKnown: 0,
      expressionsTotal: 3,
    );
    expect(r.newAccuracy, 1.0);
    expect(r.reviewAccuracy, 0.25);
    expect(r.levelAccuracy, closeTo(0.55, 0.001));
    final adj = DailyAdjuster.adjust(profile: profile, currentContentStep: 7, today: r, yesterdayAccuracy: 0.95);
    expect(adj.levelDelta, lessThan(0));
    expect(adj.nextContentStep, 8);
  });

  test('보강 영역: 듣기는 빼고, 약한 두 영역 차이가 50점 미만이면 번갈아', () {
    expect(profile.focusSkillFor(DateTime(2026, 11, 22)), Skill.speaking);
    const close = LearnerProfile(
      overall: Level(700),
      skills: {
        Skill.vocabulary: Level(720),
        Skill.grammar: Level(700),
        Skill.listening: Level(100),
        Skill.speaking: Level(690),
      },
    );
    final a = close.focusSkillFor(DateTime(2026, 11, 22));
    final b = close.focusSkillFor(DateTime(2026, 11, 23));
    expect({a, b}, {Skill.speaking, Skill.grammar});
  });
}
