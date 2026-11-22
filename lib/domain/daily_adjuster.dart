import 'level.dart';
import 'study_log.dart';

/// 하루 학습 결과.
class DailyResult {
  const DailyResult({
    required this.quizCorrect,
    required this.quizTotal,
    required this.wordsKnown,
    required this.wordsTotal,
    required this.speakingAverage,
    required this.expressionsAlreadyKnown,
    required this.expressionsTotal,
    this.reviewCorrect = 0,
    this.reviewTotal = 0,
  });

  final int quizCorrect;
  final int quizTotal;
  final int wordsKnown;
  final int wordsTotal;

  /// 말하기 평균 점수 0~100 (말하기를 안 했으면 null)
  final double? speakingAverage;
  final int expressionsAlreadyKnown;
  final int expressionsTotal;

  /// 퀴즈 중 예전에 배운 것을 묻는 복습 문항 ([quizCorrect]/[quizTotal]에 포함된 수)
  final int reviewCorrect;
  final int reviewTotal;

  int get newTotal => quizTotal - reviewTotal;
  int get newCorrect => quizCorrect - reviewCorrect;

  /// 오늘 배운 것 정답률 (방금 본 것이라 높게 나온다) → 내일 난이도에 쓴다
  double? get newAccuracy => newTotal < 3 ? null : newCorrect / newTotal;

  /// 며칠 전 배운 것 정답률 (실제로 기억하는지) → 레벨 점수에 더 크게 반영한다
  double? get reviewAccuracy => reviewTotal < 3 ? null : reviewCorrect / reviewTotal;

  /// 레벨 점수용 정답률: 복습 60% + 오늘 40%.
  /// 복습 문항이 없으면 방금 본 것만 물은 셈이라 정답률을 15% 깎아 반영한다 (레벨이 쉽게 부풀지 않게).
  double get levelAccuracy {
    if (quizTotal == 0) return 0;
    if (reviewTotal == 0) return accuracy * 0.85;
    if (newTotal == 0) return reviewCorrect / reviewTotal;
    return (reviewCorrect / reviewTotal) * 0.6 + (newCorrect / newTotal) * 0.4;
  }

  double get accuracy => quizTotal == 0 ? 0 : quizCorrect / quizTotal;
  double get wordsKnownRatio => wordsTotal == 0 ? 0 : wordsKnown / wordsTotal;
  double get expressionsKnownRatio => expressionsTotal == 0 ? 0 : expressionsAlreadyKnown / expressionsTotal;
}

/// 다음 날 학습 계획 조정 결과.
class DailyAdjustment {
  const DailyAdjustment({
    required this.profile,
    required this.levelDelta,
    required this.nextContentStep,
    required this.focusSkill,
    required this.speakingSentences,
    required this.reasons,
  });

  /// 점수가 반영된 새 프로필
  final LearnerProfile profile;

  /// 오늘 얻은 레벨 점수
  final int levelDelta;

  /// 내일 콘텐츠 난이도 (세부 단계 index)
  final int nextContentStep;

  /// 내일 집중 보강할 영역
  final Skill focusSkill;

  /// 내일 말하기 문장 수
  final int speakingSentences;

  /// 사용자에게 보여줄 조정 이유
  final List<String> reasons;
}

/// 퀴즈 정답률이 목표 구간(70~85%)에 머물도록 난이도를 자동 조절한다.
abstract final class DailyAdjuster {
  static const targetLow = 0.70;
  static const targetHigh = 0.85;

  /// 오늘 배운 것만의 정답률 목표 (직후 재인이라 더 높다)
  static const newTargetLow = 0.80;
  static const newTargetHigh = 0.92;
  static const baseSpeakingSentences = 10;

  static DailyAdjustment adjust({
    required LearnerProfile profile,
    required int currentContentStep,
    required DailyResult today,
    double? yesterdayAccuracy,
    DateTime? date,
  }) {
    // 난이도는 오늘 배운 것 정답률로, 레벨은 기억(복습) 정답률을 더 크게 본다
    final acc = today.newAccuracy ?? today.accuracy;
    // 방금 배운 것만의 정답률은 원래 높게 나오므로 목표 구간을 따로 둔다
    // 오늘 배운 것만으로 판단할 때(복습 문항이 없는 날 포함)는 직후 재인용 목표 구간을 쓴다
    final usesNew = today.newAccuracy != null;
    final low = usesNew ? newTargetLow : targetLow;
    final high = usesNew ? newTargetHigh : targetHigh;
    final levelAcc = today.levelAccuracy;
    final reasons = <String>[];

    // 1) 레벨 점수: 정답률만 반영한다 (출석만으로 레벨이 오르지 않게)
    final levelDelta = ((levelAcc - 0.75) * 40).round();

    // 2) 영역별 점수
    final skillDelta = <Skill, int>{
      Skill.grammar: ((levelAcc - 0.75) * 30).round(),
      // 듣기 문항이 생기기 전까지는 퀴즈(읽기)로 듣기 점수를 바꾸지 않는다
      Skill.listening: 0,
      Skill.vocabulary: ((today.wordsKnownRatio - 0.6) * 30).round(),
      Skill.speaking: today.speakingAverage == null ? 0 : ((today.speakingAverage! - 75) * 0.6).round(),
    };
    final newSkills = {for (final e in profile.skills.entries) e.key: e.value + (skillDelta[e.key] ?? 0)};
    final newProfile = LearnerProfile(overall: profile.overall + levelDelta, skills: newSkills);

    // 3) 콘텐츠 난이도
    var stepDelta = 0;
    final pct = (acc * 100).round();
    if (acc > high && (yesterdayAccuracy == null || yesterdayAccuracy > high)) {
      stepDelta = 1;
      reasons.add('정답률 $pct% → 표현을 조금 더 어렵게');
    } else if (acc < low) {
      stepDelta = -1;
      reasons.add('정답률 $pct% → 난이도를 한 단계 낮추고 복습을 늘려요');
    } else if (today.expressionsKnownRatio >= 2 / 3) {
      stepDelta = 1;
      reasons.add('이미 아는 표현이 많아서 한 단계 올려요');
    }
    final base = newProfile.overall.step;
    final nextStep = (currentContentStep + stepDelta).clamp(
      (base - 1).clamp(0, Level.stepCount - 1),
      (base + 2).clamp(0, Level.stepCount - 1),
    );

    // 4) 약점 보강
    final focus = newProfile.focusSkillFor(addDays(date ?? DateTime.now(), 1));
    final speaking = baseSpeakingSentences + (focus == Skill.speaking ? 2 : 0);
    reasons.add(
      focus == Skill.speaking ? '말하기 보강 → 말하기 문장 $baseSpeakingSentences개 → $speaking개' : '${focus.ko} 영역을 조금 더 출제해요',
    );

    return DailyAdjustment(
      profile: newProfile,
      levelDelta: levelDelta,
      nextContentStep: nextStep,
      focusSkill: focus,
      speakingSentences: speaking,
      reasons: reasons,
    );
  }
}
