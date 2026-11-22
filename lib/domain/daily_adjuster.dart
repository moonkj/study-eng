import 'level.dart';

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
  });

  final int quizCorrect;
  final int quizTotal;
  final int wordsKnown;
  final int wordsTotal;

  /// 말하기 평균 점수 0~100 (말하기를 안 했으면 null)
  final double? speakingAverage;
  final int expressionsAlreadyKnown;
  final int expressionsTotal;

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
  static const targetLow = 0.65;
  static const targetHigh = 0.85;
  static const baseSpeakingSentences = 10;

  static DailyAdjustment adjust({
    required LearnerProfile profile,
    required int currentContentStep,
    required DailyResult today,
    double? yesterdayAccuracy,
  }) {
    final acc = today.accuracy;
    final reasons = <String>[];

    // 1) 레벨 점수: 완료 보너스 + 정답률 기반
    final levelDelta = 2 + ((acc - 0.75) * 40).round();

    // 2) 영역별 점수
    final skillDelta = <Skill, int>{
      Skill.grammar: ((acc - 0.75) * 30).round(),
      Skill.listening: ((acc - 0.75) * 15).round(),
      Skill.vocabulary: ((today.wordsKnownRatio - 0.6) * 30).round(),
      Skill.speaking: today.speakingAverage == null ? 0 : ((today.speakingAverage! - 75) * 0.6).round(),
    };
    final newSkills = {for (final e in profile.skills.entries) e.key: e.value + (skillDelta[e.key] ?? 0)};
    final newProfile = LearnerProfile(overall: profile.overall + levelDelta, skills: newSkills);

    // 3) 콘텐츠 난이도
    var stepDelta = 0;
    final pct = (acc * 100).round();
    if (acc > targetHigh && (yesterdayAccuracy == null || yesterdayAccuracy > targetHigh)) {
      stepDelta = 1;
      reasons.add('정답률 $pct% → 표현을 조금 더 어렵게');
    } else if (acc < targetLow) {
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
    final focus = newProfile.weakestSkill;
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
