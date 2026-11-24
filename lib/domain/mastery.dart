import '../data/pack_source.dart';
import 'srs.dart';
import 'study_log.dart';

/// 표현·단어의 숙련 단계: 새로움 → 익히는 중 → 졸업 → 완전히 익힘
enum Mastery {
  fresh('새로움'),
  learning('익히는 중'),
  graduated('졸업'),
  mastered('완전히 익힘');

  const Mastery(this.ko);
  final String ko;
}

/// 복습 카드 단계로 숙련 단계를 정한다 (카드가 없으면 아직 평가 전 = 새로움)
Mastery masteryOf(ReviewCard? c) {
  if (c == null || c.stage < 0) return Mastery.fresh;
  if (c.retired) return Mastery.mastered;
  if (c.graduated) return Mastery.graduated;
  return Mastery.learning;
}

/// 익히는 중일 때 몇 칸 왔는지 (0~5, 1·3·7·14·30일 간격 중 통과한 수)
int masteryProgress(ReviewCard? c) => c == null || c.stage < 0 ? 0 : (c.stage + 1).clamp(0, Srs.intervals.length);

/// 오늘 졸업한 항목 (오늘 첫 상태에서는 졸업 전이었고 지금은 졸업)
List<String> graduatedToday(Map<String, ReviewCard?> before, Map<String, ReviewCard> cards) => [
  for (final e in before.entries)
    if (!(e.value?.graduated ?? false) && (cards[e.key]?.graduated ?? false)) e.key,
];

/// 오늘 맞힌 복습 문제 중 가장 오래전에 배운 것 (축하 문구용: "14일 전 배운 ~, 아직 기억해요")
({LearnedItem item, int days})? oldestRemembered(
  Iterable<String> correctReviewIds,
  Map<String, LearnedItem> learned,
  DateTime today,
) {
  ({LearnedItem item, int days})? best;
  for (final id in correctReviewIds) {
    final l = learned[id];
    if (l == null) continue;
    final days = daysBetween(parseDateKey(l.firstSeen), today);
    if (days >= 2 && (best == null || days > best.days)) best = (item: l, days: days);
  }
  return best;
}
