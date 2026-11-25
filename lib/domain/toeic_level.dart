/// 사용자에게 보이는 실력은 모두 토익스피킹(토스) 등급으로 보여 준다.
/// CEFR 단계(`Level`, A1.1~C1.3)는 표현·단어 난이도를 고르는 내부 축으로만 쓰고 화면에는 내지 않는다.
library;

import '../data/toeic.dart' show toeicLevels, toeicLevelIndex;
import 'toeic_feedback.dart' show MockResult, ToeicTaskRecord, estimateLevel;

/// 등급별 대표 점수 (어림값: IM1 이상은 목표 점수(`ToeicTarget.score`)와 같은 공식 구간의 아래쪽 값,
/// 그 아래 등급은 구간 안의 대략의 값)
const toeicLevelScore = {
  'NL': 30,
  'NM': 40,
  'NH': 60,
  'IL': 90,
  'IM1': 110,
  'IM2': 130,
  'IM3': 140,
  'IH': 160,
  'AL': 180,
};

/// "IM3 · 140점"
String toeicLevelLabel(String level) => '$level · ${toeicLevelScore[level.toUpperCase()] ?? 0}점';

/// CEFR 세부 단계(0=A1.1 ~ 14=C1.3)를 토스 등급으로 **대략** 바꾼다.
///
/// 공식 환산표가 없어서 목표 등급 → 표현 난이도 단계(`ToeicTarget.contentStep`:
/// IM1=A2.3, IM2=B1.1, IM3=B1.2, IH=B2.1, AL=B2.3)를 거꾸로 이은 어림값이다.
/// 화면에는 반드시 "예상"을 붙여 보여 주고, Claude 채점 기록이 생기면 채점 기준 등급으로 바꾼다.
///
/// | CEFR | A1.1 | A1.2 | A1.3 | A2.1~A2.2 | A2.3 | B1.1 | B1.2~B1.3 | B2.1~B2.2 | B2.3 이상 |
/// |------|------|------|------|-----------|------|------|-----------|-----------|-----------|
/// | 토스 | NL   | NM   | NH   | IL        | IM1  | IM2  | IM3       | IH        | AL        |
String toeicLevelForStep(int step) => switch (step) {
  <= 0 => 'NL',
  1 => 'NM',
  2 => 'NH',
  3 || 4 => 'IL',
  5 => 'IM1',
  6 => 'IM2',
  7 || 8 => 'IM3',
  9 || 10 => 'IH',
  _ => 'AL',
};

/// 표현 난이도(내부 단계)를 목표와 견주어 쉬운 말로: 설정의 '표현 난이도(자동)'
String difficultyKo(int contentStep, int targetStep) => switch (contentStep - targetStep) {
  <= -2 => '쉽게',
  -1 => '조금 쉽게',
  0 => '목표 수준',
  1 => '조금 어렵게',
  _ => '어렵게',
};

/// 지금 예상 토스 등급
class ToeicEstimate {
  const ToeicEstimate({
    required this.low,
    required this.high,
    required this.approximate,
    this.samples = 0,
    this.previous,
  });

  /// 범위의 아래·위 등급 (같으면 한 등급)
  final String low;
  final String high;

  /// 채점 기록 없이 레벨 진단(CEFR)에서 어림한 값인지 ("예상"을 붙인다)
  final bool approximate;

  /// 등급을 낸 Claude 채점 기록 수
  final int samples;

  /// 가장 최근 기록을 빼고 본 지난번 등급 (눈금에 표시, 없으면 null)
  final String? previous;

  bool get isRange => low != high;

  /// 범위의 가운데로 보는 등급 (위쪽)
  String get level => high;

  /// "IM2~IM3" 또는 "IM3 · 140점"
  String get label => isRange ? '$low~$high' : toeicLevelLabel(low);

  /// 화면 문구: 어림값이면 "예상 IM3 · 140점"
  String get display => approximate ? '예상 $label' : label;

  /// 근거 한 줄
  String get basis => approximate ? '레벨 진단으로 본 대략의 등급이에요 · 토스 말하기를 하면 채점 기준으로 바뀌어요' : '최근 채점 $samples회 기준';
}

/// 채점 기록 평균 ±[spread]점을 등급 범위로 (등급 경계 근처면 "IM2~IM3" 처럼 두 등급)
const spread = 5.0;

/// 최근 Claude 채점 기록(오늘 루틴 문항 + 모의고사)으로 예상 등급을 낸다.
/// 채점 기록이 없으면 진단 결과(CEFR 단계 [levelStep])를 어림해 "예상"으로 표시한다.
/// 기기 점수(서버 채점 아님)는 등급을 내지 않는다.
ToeicEstimate estimateToeic({
  required List<MockResult> mocks,
  required Iterable<ToeicTaskRecord> today,
  required int levelStep,
  int recent = 5,
}) {
  // 가장 최근 것부터: 오늘 루틴 → 최근 모의고사
  final samples = <double>[
    for (final r in today)
      if (r.graded) r.score.toDouble(),
    for (final m in mocks.reversed)
      if (m.graded && m.scores.any((s) => s != null)) m.average,
  ].take(recent).toList();
  if (samples.isEmpty) {
    final l = toeicLevelForStep(levelStep);
    return ToeicEstimate(low: l, high: l, approximate: true);
  }
  double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
  final m = mean(samples);
  final low = estimateLevel(m - spread), high = estimateLevel(m + spread);
  return ToeicEstimate(
    low: low,
    high: high,
    approximate: false,
    samples: samples.length,
    previous: samples.length >= 2 ? estimateLevel(mean(samples.sublist(1))) : null,
  );
}

/// 등급 눈금 위치 0.0(NL) ~ 1.0(AL)
double toeicLevelPosition(String level) {
  final i = toeicLevelIndex(level);
  return i < 0 ? 0 : i / (toeicLevels.length - 1);
}
