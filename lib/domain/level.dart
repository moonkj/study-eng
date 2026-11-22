/// 레벨 체계: CEFR A1~C1 을 각각 .1~.3 으로 나눈 15단계.
/// 내부적으로 0~1499 점수로 관리하고, 100점이 세부 단계 1칸이다.
library;

enum Cefr { a1, a2, b1, b2, c1 }

extension CefrLabel on Cefr {
  String get label => name.toUpperCase();

  String get koDescription => switch (this) {
    Cefr.a1 => '입문 — 아주 기본적인 표현',
    Cefr.a2 => '초급 — 익숙한 상황의 짧은 대화',
    Cefr.b1 => '중급 — 일상 대화 가능',
    Cefr.b2 => '중상급 — 다양한 주제로 자연스럽게',
    Cefr.c1 => '고급 — 유창하고 정확하게',
  };
}

/// 학습 영역 4개.
enum Skill { vocabulary, grammar, listening, speaking }

extension SkillLabel on Skill {
  String get ko => switch (this) {
    Skill.vocabulary => '어휘',
    Skill.grammar => '문장 구성',
    Skill.listening => '듣기',
    Skill.speaking => '말하기',
  };
}

class Level implements Comparable<Level> {
  const Level(int score) : score = score < 0 ? 0 : (score > maxScore ? maxScore : score);

  /// 세부 단계 index(0~14)에서 시작점 점수로 만든다.
  factory Level.fromStep(int step) => Level(step.clamp(0, stepCount - 1) * pointsPerStep);

  static const pointsPerStep = 100;
  static const stepCount = 15;
  static const maxScore = stepCount * pointsPerStep - 1;

  final int score;

  /// 0(A1.1) ~ 14(C1.3)
  int get step => score ~/ pointsPerStep;

  Cefr get cefr => Cefr.values[step ~/ 3];

  /// 1~3
  int get sub => step % 3 + 1;

  /// "B1.2"
  String get label => '${cefr.label}.$sub';

  /// 다음 세부 단계까지 진행률 0.0~1.0
  double get progressToNext => (score % pointsPerStep) / pointsPerStep;

  bool get isMax => step == stepCount - 1;

  Level get next => isMax ? this : Level.fromStep(step + 1);

  Level operator +(int points) => Level(score + points);

  @override
  int compareTo(Level other) => score.compareTo(other.score);

  @override
  bool operator ==(Object other) => other is Level && other.score == score;

  @override
  int get hashCode => score.hashCode;

  @override
  String toString() => 'Level($label, $score)';
}

/// 영역별 레벨을 포함한 학습자 프로필.
class LearnerProfile {
  const LearnerProfile({required this.overall, required this.skills});

  final Level overall;
  final Map<Skill, Level> skills;

  Skill get weakestSkill => skills.entries.reduce((a, b) => a.value <= b.value ? a : b).key;

  Skill get strongestSkill => skills.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

  LearnerProfile copyWith({Level? overall, Map<Skill, Level>? skills}) =>
      LearnerProfile(overall: overall ?? this.overall, skills: skills ?? this.skills);
}

extension LevelCompare on Level {
  bool operator <=(Level other) => score <= other.score;
  bool operator >=(Level other) => score >= other.score;
}
