import '../data/grade_source.dart' show ToeicTaskType;
import '../data/toeic.dart' show ToeicBank, ToeicBlock, ToeicDailySet, ToeicTarget, dailySetFor;
import 'study_log.dart' show parseDateKey;
import 'toeic_feedback.dart' show MockResult;

/// 하루 한 유형의 루틴 점수 (Claude 채점분만)
/// - [first]: 그날 처음 채점된 시도 → 약점 판단(실력)
/// - [best]: 다시 해서 가장 높았던 점수 → 성장(노력) 표시
class ToeicDayScore {
  const ToeicDayScore({this.first, required this.best});

  /// 예전 기록(채점 여부·첫 시도를 알 수 없음)은 null: 약점 계산에서 뺀다
  final int? first;
  final int best;

  Map<String, Object?> toJson() => {'first': ?first, 'best': best};

  /// 새 형식 {first, best} 와 예전 형식(숫자 하나 = 그날 최고 점수, 기기 점수 섞임) 모두 읽는다
  static ToeicDayScore? fromJson(Object? raw) {
    int? n(Object? v) => v is num ? v.toInt().clamp(0, 100) : null;
    if (raw is num) return ToeicDayScore(best: n(raw)!);
    if (raw is! Map) return null;
    final first = n(raw['first']), best = n(raw['best']);
    if (best == null && first == null) return null;
    return ToeicDayScore(first: first, best: best ?? first!);
  }

  @override
  bool operator ==(Object other) => other is ToeicDayScore && other.first == first && other.best == best;

  @override
  int get hashCode => Object.hash(first, best);

  @override
  String toString() => 'ToeicDayScore($first, $best)';
}

/// 토스 루틴 점수 (날짜 → 유형(wire) → 그날 점수)
typedef ToeicLog = Map<String, Map<String, ToeicDayScore>>;

/// 모의고사 문항(Q1~Q11) 순서대로의 유형
const mockQuestionTypes = [
  ToeicTaskType.readAloud,
  ToeicTaskType.readAloud,
  ToeicTaskType.picture,
  ToeicTaskType.picture,
  ToeicTaskType.respond,
  ToeicTaskType.respond,
  ToeicTaskType.respond,
  ToeicTaskType.info,
  ToeicTaskType.info,
  ToeicTaskType.info,
  ToeicTaskType.opinion,
];

/// 유형 이름
const toeicTypeKo = {
  ToeicTaskType.readAloud: '문장 읽기',
  ToeicTaskType.picture: '사진 묘사',
  ToeicTaskType.respond: '질문 답하기',
  ToeicTaskType.info: '표 보고 답하기',
  ToeicTaskType.opinion: '의견 말하기',
};

/// 매일 돌아가는 묶음 ↔ 유형
const blockType = {
  ToeicBlock.respond: ToeicTaskType.respond,
  ToeicBlock.info: ToeicTaskType.info,
  ToeicBlock.opinion: ToeicTaskType.opinion,
};

/// 한 유형의 최근 점수
class TypeStat {
  const TypeStat({required this.type, required this.average, required this.samples});
  final ToeicTaskType type;

  /// 최근 기록 평균 (0~100)
  final double average;
  final int samples;
}

/// 약점으로 보려면 유형마다 최소 이만큼 기록이 있어야 한다
const minSamples = 2;

/// 약점으로 보려면 다음으로 낮은 유형보다 이만큼 낮아야 한다 (점수가 비슷하면 약점이라고 하지 않는다)
const weakGap = 5;

/// 유형별 최근 [recent]번 점수의 평균. **Claude 채점 점수만** 쓴다 (기기 점수는 분량만 채워도 높게 나와 약점을 가린다).
/// [daily]: 루틴 점수 중 그날 **첫 시도**([ToeicDayScore.first], 다시 하기로 약점이 사라져 보이지 않게),
/// [mocks]: 모의고사의 채점된 문항 (유형별 평균을 한 번으로 친다).
/// [before] 가 있으면 그 날짜 전 기록만 쓴다 (오늘 하는 동안 오늘의 약점이 바뀌지 않게).
Map<ToeicTaskType, TypeStat> typeStats(ToeicLog daily, List<MockResult> mocks, {String? before, int recent = 5}) {
  final samples = <ToeicTaskType, List<(String, int)>>{};
  void add(String date, ToeicTaskType type, int score) {
    if (before != null && date.compareTo(before) >= 0) return;
    (samples[type] ??= []).add((date, score));
  }

  for (final day in daily.entries) {
    for (final e in day.value.entries) {
      final type = ToeicTaskType.fromWire(e.key);
      final first = e.value.first;
      if (type != null && first != null) add(day.key, type, first);
    }
  }
  for (final m in mocks) {
    final byType = <ToeicTaskType, List<int>>{};
    for (var i = 0; i < mockQuestionTypes.length; i++) {
      final s = m.gradedPercent(i);
      if (s != null) (byType[mockQuestionTypes[i]] ??= []).add(s);
    }
    for (final e in byType.entries) {
      add(m.date, e.key, (e.value.reduce((a, b) => a + b) / e.value.length).round());
    }
  }
  return {
    for (final e in samples.entries)
      e.key: () {
        final list = [...e.value]..sort((a, b) => b.$1.compareTo(a.$1));
        final top = list.take(recent).map((x) => x.$2).toList();
        return TypeStat(type: e.key, average: top.reduce((a, b) => a + b) / top.length, samples: top.length);
      }(),
  };
}

/// 기록이 충분한 유형 중 확실히 낮은 하나 (없으면 null)
ToeicTaskType? weakestOf(Iterable<TypeStat> stats) {
  final list = stats.where((s) => s.samples >= minSamples).toList()..sort((a, b) => a.average.compareTo(b.average));
  if (list.length < 2) return null;
  return list[1].average - list[0].average >= weakGap ? list[0].type : null;
}

/// 전체 유형 중 약점
ToeicTaskType? weakestType(Map<ToeicTaskType, TypeStat> stats) => weakestOf(stats.values);

/// 돌아가는 묶음(질문 답하기·표 보고 답하기·의견 말하기) 중 약점. 오늘의 세트에 더 자주 넣는다.
ToeicBlock? weakBlock(Map<ToeicTaskType, TypeStat> stats) {
  final type = weakestOf([
    for (final t in blockType.values)
      if (stats[t] != null) stats[t]!,
  ]);
  if (type == null) return null;
  return blockType.entries.firstWhere((e) => e.value == type).key;
}

/// 그날 [date] 의 토스 세트: 그날 전 기록으로 약점 묶음을 정해 [dailySetFor] 로 고른다.
/// 오늘 화면(toeicDailyProvider)과 맞춤 팩 요청이 같은 세트를 쓰도록 둘 다 이 함수를 부른다.
ToeicDailySet toeicSetOn(ToeicBank bank, String date, ToeicTarget target, ToeicLog log, List<MockResult> mocks) =>
    dailySetFor(bank, parseDateKey(date), target, focus: weakBlock(typeStats(log, mocks, before: date)));

/// 가장 최근에 다시 해서 오른 기록 (그날 첫 시도 → 최고, 없으면 null). 기록 탭에서 성장을 보여 준다.
({String date, ToeicTaskType type, int first, int best})? latestRetryGrowth(ToeicLog daily) {
  final days = daily.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final d in days) {
    for (final type in mockQuestionTypes.toSet()) {
      final s = daily[d]![type.wire];
      if (s?.first != null && s!.best > s.first!) return (date: d, type: type, first: s.first!, best: s.best);
    }
  }
  return null;
}

/// 날짜별 루틴 점수에 이번 시도를 넣는다 (최근 [keep]일만 남긴다).
/// Claude 채점([graded])이 아닌 시도는 넣지 않는다. 그날 처음 채점된 시도는 [ToeicDayScore.first] 로 고정하고,
/// 다시 하면 [ToeicDayScore.best] 만 올라간다.
ToeicLog addDailyScore(
  ToeicLog daily,
  String date,
  ToeicTaskType type,
  int score, {
  required bool graded,
  int keep = 60,
}) {
  if (!graded) return daily;
  final day = {...?daily[date]};
  final before = day[type.wire];
  final next = ToeicDayScore(
    first: before?.first ?? score,
    best: before == null || score > before.best ? score : before.best,
  );
  if (next == before) return daily;
  day[type.wire] = next;
  final out = {...daily, date: day};
  if (out.length <= keep) return out;
  final keys = out.keys.toList()..sort();
  for (final k in keys.take(out.length - keep)) {
    out.remove(k);
  }
  return out;
}
