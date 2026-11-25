import '../data/grade_source.dart' show ToeicTaskType;
import '../data/toeic.dart' show toeicLevels, toeicLevelIndex;
import 'speech_score.dart';

/// 비교용으로 소문자·문장부호 없이
String _norm(String s) =>
    ' ${s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]+"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

int wordCount(String text) => text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

/// 말한 내용에 [phrase] 가 들어 있는지 (대소문자 무시, "~"·"..." 자리는 아무 말이나 와도 된다)
bool usedPhrase(String transcript, String phrase) {
  final t = _norm(transcript);
  final parts = phrase.split(RegExp(r'~|\.\.\.|…|\(.*?\)|/')).map(_norm).where((p) => p.trim().isNotEmpty).toList();
  if (parts.isEmpty) return false;
  var from = 0;
  for (final p in parts) {
    final i = t.indexOf(p, from);
    if (i < 0) return false;
    from = i + p.length - 1;
  }
  return true;
}

List<String> usedPhrases(String transcript, List<String> phrases) => [
  for (final p in phrases)
    if (usedPhrase(transcript, p)) p,
];

/// 서버 없이 매기는 대략의 점수 (0~100)
/// - 문장 읽기: 원문과 얼마나 같게 들렸는지
/// - 나머지: 제한 시간에 맞는 분량(초당 약 1.6단어의 60%)을 채웠는지 + 핵심 표현을 썼는지
int offlineScore({
  required ToeicTaskType type,
  required String transcript,
  required int limitSeconds,
  String? reference,
  List<String> keyPhrases = const [],
}) {
  if (transcript.trim().isEmpty) return 0;
  if (type == ToeicTaskType.readAloud && reference != null) return scoreSpeech(reference, transcript).score;
  final expected = limitSeconds * 1.6 * 0.6;
  final coverage = (wordCount(transcript) / expected).clamp(0.0, 1.0);
  final phrases = keyPhrases.isEmpty ? coverage : usedPhrases(transcript, keyPhrases).length / keyPhrases.length;
  return (100 * (0.75 * coverage + 0.25 * phrases.clamp(0.0, 1.0))).round();
}

/// 평균 점수(0~100)로 본 대략의 등급 (한 문항·한 묶음용. 모의고사 등급은 [estimateMockLevel])
String estimateLevel(double percent) => switch (percent) {
  >= 90 => 'AL',
  >= 80 => 'IH',
  >= 70 => 'IM3',
  >= 62 => 'IM2',
  >= 55 => 'IM1',
  >= 45 => 'IL',
  >= 30 => 'NH',
  >= 15 => 'NM',
  _ => 'NL',
};

// ───────────────────────── 모의고사 등급 추정 ─────────────────────────
// ETS 는 환산식을 공개하지 않는다. 아래 값은 강사 경험칙(3기 토론 라운드 4)이고, 실제 시험 결과를 받으면 보정한다.

/// 모의고사 문항별 만점 (ETS 원점수: Q1~Q10 0~3, Q11 0~5)
const mockMaxPoints = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5];

/// 모의고사 문항별 가중치: 등급을 크게 가르는 문항일수록 크다 (Q1-2 1 · Q3-4 1.5 · Q5-10 2 · Q11 4, 합 21)
const mockWeights = [1.0, 1.0, 1.5, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0];

/// 가중 원점수 비율(0~100) → 등급 추정표 (이 값 이상이면 그 등급, 10 미만은 NL).
/// 경계는 등급별 전형적인 답안 사이의 가운데 값이다.
/// 예: IM2 ≈ 67 (Q1-4 2~3점 · Q5-10 2점 · Q11 2~3점), IM3 ≈ 82 (Q1-4 대부분 3점 · Q5-10 2~3점 · Q11 3점),
/// IH ≈ 92 (Q1-4 3점 · Q5-10 거의 3점 · Q11 4점)
const mockLevelTable = [
  (min: 95.0, level: 'AL'),
  (min: 87.0, level: 'IH'),
  (min: 75.0, level: 'IM3'),
  (min: 60.0, level: 'IM2'),
  (min: 45.0, level: 'IM1'),
  (min: 30.0, level: 'IL'),
  (min: 20.0, level: 'NH'),
  (min: 10.0, level: 'NM'),
];

/// 등급을 내려면 채점된 문항의 가중치가 전체의 이만큼은 되어야 한다 (채점이 몇 문항 실패해도 대부분 있으면 낸다)
const mockMinGradedShare = 0.6;

/// 등급 범위 ("IM2~IM3"). 한 번의 모의고사로 한 등급을 단정하지 않는다.
class LevelRange {
  const LevelRange(this.low, this.high);
  final String low;
  final String high;

  String get label => low == high ? low : '$low~$high';

  /// "IM2~IM3" / "IM3" 을 읽는다 (등급이 아니면 null)
  static LevelRange? parse(String raw) {
    final parts = raw.split('~').map((p) => p.trim().toUpperCase()).toList();
    if (parts.length > 2 || parts.any((p) => toeicLevelIndex(p) < 0)) return null;
    final a = parts.first, b = parts.last;
    return toeicLevelIndex(a) <= toeicLevelIndex(b) ? LevelRange(a, b) : LevelRange(b, a);
  }
}

/// 문항별 원점수([points], 채점 안 된 문항은 null)의 가중 비율 (0~100). 채점된 문항이 모자라면 null.
/// 채점 안 된 문항은 빼고 남은 가중치로 나눈다.
double? weightedMockPercent(List<int?> points) {
  var got = 0.0, weight = 0.0;
  for (var i = 0; i < points.length && i < mockWeights.length; i++) {
    final p = points[i];
    if (p == null) continue;
    got += mockWeights[i] * p.clamp(0, mockMaxPoints[i]) / mockMaxPoints[i];
    weight += mockWeights[i];
  }
  final total = mockWeights.reduce((a, b) => a + b);
  if (weight <= 0 || weight / total < mockMinGradedShare) return null;
  return 100 * got / weight;
}

/// 모의고사 예상 등급 범위. Claude 채점 원점수로만 계산하고, 기기 점수만 있으면 null (등급을 내지 않는다).
/// 범위: 추정표에서 들어간 등급 칸의 아래쪽 절반이면 한 단계 아래와, 위쪽 절반이면 한 단계 위와 묶는다.
/// (NL 칸 아래쪽 절반·AL 칸 위쪽 절반만 한 등급)
LevelRange? estimateMockLevel(List<int?> points) {
  final p = weightedMockPercent(points);
  if (p == null) return null;
  // 낮은 등급부터: (등급, 칸 아래 경계, 칸 위 경계)
  final bands = [
    (level: toeicLevels.first, lo: 0.0, hi: mockLevelTable.last.min),
    for (var i = mockLevelTable.length - 1; i >= 0; i--)
      (level: mockLevelTable[i].level, lo: mockLevelTable[i].min, hi: i == 0 ? 100.0 : mockLevelTable[i - 1].min),
  ];
  final i = bands.lastIndexWhere((b) => p >= b.lo);
  final b = bands[i];
  if (p >= (b.lo + b.hi) / 2) return LevelRange(b.level, bands[(i + 1).clamp(0, bands.length - 1)].level);
  return LevelRange(bands[(i - 1).clamp(0, bands.length - 1)].level, b.level);
}

/// 오늘 루틴에서 한 토스 문항 결과 (저장용)
class ToeicTaskRecord {
  const ToeicTaskRecord({
    required this.type,
    required this.score,
    this.graded = false,
    this.words = 0,
    this.seconds = 0,
    this.limit = 0,
  });

  final ToeicTaskType type;

  /// 0~100 (서버 채점이면 그 점수, 아니면 기기에서 계산한 대략의 점수)
  final int score;
  final bool graded;
  final int words;

  /// 말한 시간 / 제한 시간 (문항이 여러 개인 묶음은 합)
  final int seconds;
  final int limit;

  Map<String, Object?> toJson() => {
    'type': type.wire,
    'score': score,
    'graded': graded,
    'words': words,
    'seconds': seconds,
    'limit': limit,
  };

  static ToeicTaskRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = ToeicTaskType.fromWire(raw['type']);
    final score = raw['score'];
    if (type == null || score is! num) return null;
    int n(Object? v) => v is num ? v.toInt() : 0;
    return ToeicTaskRecord(
      type: type,
      score: score.toInt().clamp(0, 100),
      graded: raw['graded'] == true,
      words: n(raw['words']),
      seconds: n(raw['seconds']),
      limit: n(raw['limit']),
    );
  }
}

/// 모의고사 하나를 구분하는 값
String mockKey(MockResult m) => '${m.date}|${m.level}|${m.scores.join(',')}';

/// 모의고사 한 번의 결과 (저장용)
class MockResult {
  const MockResult({
    required this.date,
    required this.level,
    required this.target,
    this.scores = const [],
    this.points = const [],
    this.graded = false,
  });

  /// 본 날 (yyyy-MM-dd)
  final String date;

  /// 예상 등급 범위 ("IM2~IM3"). Claude 채점이 모자라 등급을 못 냈으면 빈 값. 예전 기록은 한 등급("IM3")
  final String level;

  /// 볼 때의 목표 등급
  final String target;

  /// 문항별 점수 (Q1~Q11, 0~100, 답하지 않았으면 null). 채점이 안 된 문항은 기기 점수
  final List<int?> scores;

  /// 문항별 Claude 채점 원점수 (Q1~Q10 0~3, Q11 0~5, 채점 안 된 문항은 null). 예전 기록은 비어 있다
  final List<int?> points;

  /// 예상 등급이 Claude 채점으로 계산됐는지 (예전 기록: 모든 문항이 서버 채점이었는지)
  final bool graded;

  /// 예상 등급 범위. Claude 채점이 아니면 null (예전 기기 점수 등급도 보여 주지 않는다)
  LevelRange? get estimate => graded ? LevelRange.parse(level) : null;

  /// 문항(0부터)의 Claude 채점 점수 (0~100, 없으면 null). 약점 통계는 이것만 쓴다.
  int? gradedPercent(int i) {
    if (points.isNotEmpty) {
      final p = i < points.length && i < mockMaxPoints.length ? points[i] : null;
      return p == null ? null : (p * 100 / mockMaxPoints[i]).round().clamp(0, 100);
    }
    // 예전 기록: 모든 문항이 서버 채점이었을 때만
    return graded && i < scores.length ? scores[i] : null;
  }

  double get average {
    final s = scores.whereType<int>().toList();
    return s.isEmpty ? 0 : s.reduce((a, b) => a + b) / s.length;
  }

  Map<String, Object?> toJson() => {
    'date': date,
    'level': level,
    'target': target,
    'scores': scores,
    if (points.isNotEmpty) 'points': points,
    'graded': graded,
  };

  static MockResult? fromJson(Object? raw) {
    if (raw is! Map || raw['date'] is! String || raw['level'] is! String) return null;
    List<int?> ints(Object? v) => [for (final s in (v is List ? v : const [])) s is num ? s.toInt() : null];
    return MockResult(
      date: raw['date'] as String,
      level: raw['level'] as String,
      target: raw['target'] as String? ?? '',
      scores: ints(raw['scores']),
      points: ints(raw['points']),
      graded: raw['graded'] == true,
    );
  }
}
