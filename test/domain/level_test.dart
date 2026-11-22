import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/domain/level.dart';

void main() {
  group('Level', () {
    test('점수를 CEFR 세부 단계 라벨로 바꾼다', () {
      expect(const Level(0).label, 'A1.1');
      expect(const Level(299).label, 'A1.3');
      expect(const Level(300).label, 'A2.1');
      expect(const Level(764).label, 'B1.2');
      expect(const Level(1499).label, 'C1.3');
    });

    test('범위를 벗어난 점수는 0~1499로 고정된다', () {
      expect(const Level(-50).score, 0);
      expect(const Level(5000).score, Level.maxScore);
      expect((const Level(1490) + 100).isMax, isTrue);
    });

    test('다음 단계와 진행률', () {
      const l = Level(764);
      expect(l.progressToNext, closeTo(0.64, 1e-9));
      expect(l.next.label, 'B1.3');
      expect(Level.fromStep(14).next.label, 'C1.3');
    });

    test('가장 약한/강한 영역을 찾는다', () {
      const p = LearnerProfile(
        overall: Level(700),
        skills: {
          Skill.vocabulary: Level(900),
          Skill.grammar: Level(700),
          Skill.listening: Level(650),
          Skill.speaking: Level(400),
        },
      );
      expect(p.weakestSkill, Skill.speaking);
      expect(p.strongestSkill, Skill.vocabulary);
    });
  });
}
