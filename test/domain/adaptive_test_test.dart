import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/domain/adaptive_test.dart';
import 'package:todaye/domain/level.dart';

/// 실력이 [abilityStep] 인 가상의 학습자: 그보다 쉬운 문항은 맞히고 어려운 문항은 틀린다.
LearnerProfile simulate(int abilityStep, {Map<Skill, int> perSkill = const {}}) {
  final t = AdaptiveTest();
  while (!t.isFinished) {
    final skill = t.nextSkill;
    final ability = perSkill[skill] ?? abilityStep;
    t.record(t.nextStep <= ability ? Answer.correct : Answer.wrong);
  }
  return t.result();
}

void main() {
  test('A2.1 난이도에서 시작해 정답이면 2칸 올린다', () {
    final t = AdaptiveTest();
    expect(t.nextStep, 3);
    t.record(Answer.correct);
    expect(t.nextStep, 5);
  });

  test('방향이 한 번 바뀌면 1칸씩 움직인다', () {
    final t = AdaptiveTest();
    t.record(Answer.correct); // 3 → 5
    t.record(Answer.wrong); // 5 → 4 (보폭 1)
    expect(t.nextStep, 4);
    t.record(Answer.correct);
    expect(t.nextStep, 5);
  });

  test('"잘 모르겠어요"는 오답처럼 난이도를 내린다', () {
    final t = AdaptiveTest();
    t.record(Answer.unsure);
    expect(t.nextStep, 1);
  });

  test('12문항이 끝나면 더 기록할 수 없다', () {
    final t = AdaptiveTest();
    for (var i = 0; i < 12; i++) {
      t.record(Answer.correct);
    }
    expect(t.isFinished, isTrue);
    expect(() => t.record(Answer.correct), throwsStateError);
  });

  test('실력 수준을 1단계 이내로 추정한다', () {
    for (final ability in [2, 5, 7, 10, 12]) {
      final p = simulate(ability);
      expect((p.overall.step - ability).abs(), lessThanOrEqualTo(1), reason: '실력 $ability 단계 → 추정 ${p.overall.label}');
    }
  });

  test('영역별 실력 차이를 구분한다', () {
    final p = simulate(7, perSkill: {Skill.speaking: 3, Skill.vocabulary: 9});
    expect(p.weakestSkill, Skill.speaking);
    expect(p.skills[Skill.speaking]!.step, lessThan(p.skills[Skill.vocabulary]!.step));
  });

  test('연속 정답 수를 센다', () {
    final t = AdaptiveTest();
    t.record(Answer.wrong);
    t.record(Answer.correct);
    t.record(Answer.correct);
    expect(t.correctStreak, 2);
  });
}
