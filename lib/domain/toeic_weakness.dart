import '../data/grade_source.dart' show ToeicTaskType;
import '../data/toeic.dart' show ToeicBlock;
import 'toeic_feedback.dart' show MockResult;

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

/// 유형별 최근 [recent]번 점수의 평균.
/// [daily]: 날짜 → 유형(wire) → 그날 루틴 점수, [mocks]: 모의고사 (유형별 평균을 한 번으로 친다).
/// [before] 가 있으면 그 날짜 전 기록만 쓴다 (오늘 하는 동안 오늘의 약점이 바뀌지 않게).
Map<ToeicTaskType, TypeStat> typeStats(
  Map<String, Map<String, int>> daily,
  List<MockResult> mocks, {
  String? before,
  int recent = 5,
}) {
  final samples = <ToeicTaskType, List<(String, int)>>{};
  void add(String date, ToeicTaskType type, int score) {
    if (before != null && date.compareTo(before) >= 0) return;
    (samples[type] ??= []).add((date, score));
  }

  for (final day in daily.entries) {
    for (final e in day.value.entries) {
      final type = ToeicTaskType.fromWire(e.key);
      if (type != null) add(day.key, type, e.value);
    }
  }
  for (final m in mocks) {
    final byType = <ToeicTaskType, List<int>>{};
    for (var i = 0; i < m.scores.length && i < mockQuestionTypes.length; i++) {
      final s = m.scores[i];
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

/// 날짜별 루틴 점수에 오늘 점수를 넣는다 (같은 날 같은 유형은 높은 점수, 최근 [keep]일만 남긴다)
Map<String, Map<String, int>> addDailyScore(
  Map<String, Map<String, int>> daily,
  String date,
  ToeicTaskType type,
  int score, {
  int keep = 60,
}) {
  final day = {...?daily[date]};
  final before = day[type.wire];
  if (before != null && before >= score) return daily;
  day[type.wire] = score;
  final out = {...daily, date: day};
  if (out.length <= keep) return out;
  final keys = out.keys.toList()..sort();
  for (final k in keys.take(out.length - keep)) {
    out.remove(k);
  }
  return out;
}
