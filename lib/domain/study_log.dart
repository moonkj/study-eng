/// 날짜별 학습 기록과 연속 학습일 계산.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// 하루 루틴을 끝낸 날의 기록
class DayRecord {
  const DayRecord({required this.accuracy, required this.levelScore, this.speakingAverage, this.newAccuracy});

  /// 퀴즈 정답률 0~1
  final double accuracy;

  /// 그날 루틴을 끝낸 뒤의 전체 레벨 점수
  final int levelScore;
  final double? speakingAverage;

  /// 그날 배운 것만의 퀴즈 정답률 (난이도 판단용, 문항이 적으면 null)
  final double? newAccuracy;

  Map<String, Object?> toJson() => {
    'accuracy': accuracy,
    'levelScore': levelScore,
    'speaking': speakingAverage,
    if (newAccuracy != null) 'new': newAccuracy,
  };

  factory DayRecord.fromJson(Map<String, Object?> j) => DayRecord(
    accuracy: (j['accuracy'] as num).toDouble(),
    levelScore: (j['levelScore'] as num).toInt(),
    speakingAverage: (j['speaking'] as num?)?.toDouble(),
    newAccuracy: (j['new'] as num?)?.toDouble(),
  );
}

/// 연속 학습 상태
class StreakInfo {
  const StreakInfo({required this.days, required this.restsLeft, required this.restDays});

  /// 연속 학습일 (쉬는 날은 세지 않는다)
  final int days;

  /// 남은 '쉬는 날' 수 (7일 연속마다 1개, 최대 [maxRests]개)
  final int restsLeft;

  /// 쉬는 날로 메워진 날짜 키
  final Set<String> restDays;

  static const maxRests = 2;
  static const earnEvery = 7;
}

/// 연속 학습일과 '쉬는 날'을 계산한다.
/// 7일 연속으로 공부할 때마다 쉬는 날이 1개(최대 2개) 생기고, 하루 빠지면 자동으로 써서 기록을 지킨다.
/// 쉬는 날이 없을 때 빠지면 0부터 다시 시작한다. 오늘은 아직 하루가 끝나지 않았으므로 빠진 날로 치지 않는다.
StreakInfo computeStreakInfo(Iterable<String> studiedKeys, DateTime today) {
  final days = studiedKeys.toSet();
  if (days.isEmpty) return const StreakInfo(days: 0, restsLeft: 0, restDays: {});
  DateTime utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  final first = days.map(parseDateKey).map(utc).reduce((a, b) => a.isBefore(b) ? a : b);
  final end = utc(today);
  var run = 0, rests = 0, sinceEarn = 0;
  final restDays = <String>{};
  for (var d = first; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final key = dateKey(d);
    if (days.contains(key)) {
      run++;
      sinceEarn++;
      if (sinceEarn == StreakInfo.earnEvery) {
        sinceEarn = 0;
        if (rests < StreakInfo.maxRests) rests++;
      }
    } else if (d == end) {
      break; // 오늘은 아직 기회가 있다
    } else if (rests > 0 && run > 0) {
      rests--;
      restDays.add(key);
    } else {
      run = 0;
      sinceEarn = 0;
    }
  }
  return StreakInfo(days: run, restsLeft: rests, restDays: restDays);
}

/// 쉬는 날 없이, 오늘 또는 어제까지 끊기지 않고 이어진 학습일 수.
/// 오늘 아직 안 했어도 어제까지 이어졌으면 연속 기록은 살아 있다.
int computeStreak(Iterable<String> studiedKeys, DateTime today) {
  final days = studiedKeys.toSet();
  var cursor = dateOnly(today);
  if (!days.contains(dateKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (days.contains(dateKey(cursor))) {
    streak++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return streak;
}

/// [today] 이전의 가장 최근 학습일 기록
DayRecord? previousRecord(Map<String, DayRecord> log, DateTime today) {
  final key = dateKey(today);
  final keys = log.keys.where((k) => k.compareTo(key) < 0).toList()..sort();
  return keys.isEmpty ? null : log[keys.last];
}

/// 지금까지 가장 길게 이어진 연속 학습일
int computeLongestStreak(Iterable<String> studiedKeys) {
  // 서머타임 등으로 하루가 23시간이 되는 경우를 피하려고 UTC 날짜로 비교한다
  final days = studiedKeys.toSet().map((k) {
    final d = parseDateKey(k);
    return DateTime.utc(d.year, d.month, d.day);
  }).toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in days) {
    run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}
