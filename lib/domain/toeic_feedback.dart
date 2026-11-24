import '../data/grade_source.dart' show ToeicTaskType;
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

/// 평균 점수(0~100)로 본 예상 등급
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
    this.graded = false,
  });

  /// 본 날 (yyyy-MM-dd)
  final String date;

  /// 예상 등급 (IM3 등)
  final String level;

  /// 볼 때의 목표 등급
  final String target;

  /// 문항별 점수 (Q1~Q11, 0~100, 답하지 않았으면 null)
  final List<int?> scores;

  /// 서버 채점 결과인지
  final bool graded;

  double get average {
    final s = scores.whereType<int>().toList();
    return s.isEmpty ? 0 : s.reduce((a, b) => a + b) / s.length;
  }

  Map<String, Object?> toJson() => {'date': date, 'level': level, 'target': target, 'scores': scores, 'graded': graded};

  static MockResult? fromJson(Object? raw) {
    if (raw is! Map || raw['date'] is! String || raw['level'] is! String) return null;
    return MockResult(
      date: raw['date'] as String,
      level: raw['level'] as String,
      target: raw['target'] as String? ?? '',
      scores: [for (final s in (raw['scores'] is List ? raw['scores'] as List : const [])) s is num ? s.toInt() : null],
      graded: raw['graded'] == true,
    );
  }
}
