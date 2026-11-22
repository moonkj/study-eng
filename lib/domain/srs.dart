/// 간격 반복(SRS) 복습 스케줄.
library;

/// 단어 카드 자가 평가
enum SelfRating { dontKnow, confusing, know }

class ReviewCard {
  const ReviewCard({required this.itemId, required this.stage, required this.due, this.lapses = 0, this.lastReviewed});

  /// 처음 볼 때 카드
  factory ReviewCard.fresh(String itemId, DateTime today) =>
      ReviewCard(itemId: itemId, stage: -1, due: _dateOnly(today));

  final String itemId;

  /// -1: 새 카드, 0..4: [Srs.intervals] 단계, 5: 졸업
  final int stage;
  final DateTime due;
  final int lapses;

  /// 마지막으로 평가·답한 날 (같은 날 다시 맞힌 것은 간격 인출로 치지 않기 위해)
  final DateTime? lastReviewed;

  bool get graduated => stage >= Srs.intervals.length;

  bool isDue(DateTime today) => !graduated && !due.isAfter(_dateOnly(today));

  ReviewCard copyWith({int? stage, DateTime? due, int? lapses, DateTime? lastReviewed}) => ReviewCard(
    itemId: itemId,
    stage: stage ?? this.stage,
    due: due ?? this.due,
    lapses: lapses ?? this.lapses,
    lastReviewed: lastReviewed ?? this.lastReviewed,
  );
}

abstract final class Srs {
  /// 1 → 3 → 7 → 14 → 30일, 그 다음 졸업
  static const intervals = [1, 3, 7, 14, 30];

  /// 단어 카드 버튼: 몰라요=내일, 헷갈려요=3일 뒤, 알아요=7일 뒤
  static ReviewCard rate(ReviewCard card, SelfRating rating, DateTime today) {
    final stage = switch (rating) {
      SelfRating.dontKnow => 0,
      SelfRating.confusing => 1,
      SelfRating.know => card.stage >= 2 ? card.stage + 1 : 2,
    };
    return _schedule(card, stage, today, lapse: rating == SelfRating.dontKnow && card.stage >= 0);
  }

  /// 퀴즈 결과
  /// - 맞히면 다음 단계. 단, 오늘 이미 평가한 카드를 다시 맞힌 것은 방금 본 것이라 단계를 올리지 않는다.
  /// - 틀리면 처음으로 돌리지 않고 두 단계만 내린다 (잘 알던 것을 한 번 틀렸다고 모두 잃지 않게).
  static ReviewCard answer(ReviewCard card, {required bool correct, required DateTime today}) {
    final sameDay = card.lastReviewed != null && _dateOnly(card.lastReviewed!) == _dateOnly(today);
    if (correct && sameDay) return card;
    final stage = correct ? (card.stage < 0 ? 0 : card.stage + 1) : (card.stage - 2).clamp(0, intervals.length - 1);
    return _schedule(card, stage, today, lapse: !correct);
  }

  static int intervalDaysFor(SelfRating rating) => switch (rating) {
    SelfRating.dontKnow => intervals[0],
    SelfRating.confusing => intervals[1],
    SelfRating.know => intervals[2],
  };

  static ReviewCard _schedule(ReviewCard card, int stage, DateTime today, {bool lapse = false}) {
    final base = _dateOnly(today);
    if (stage >= intervals.length) {
      return card.copyWith(stage: intervals.length, due: base.add(const Duration(days: 3650)), lastReviewed: base);
    }
    return card.copyWith(
      stage: stage,
      due: base.add(Duration(days: intervals[stage])),
      lapses: card.lapses + (lapse ? 1 : 0),
      lastReviewed: base,
    );
  }

  /// 오늘 복습할 카드 (자주 틀린 것 먼저, 그다음 오래 밀린 순, 최대 [limit]개)
  static List<ReviewCard> dueToday(Iterable<ReviewCard> cards, DateTime today, {int limit = 5}) {
    final due = cards.where((c) => c.isDue(today)).toList()
      ..sort((a, b) {
        final hard = (b.lapses >= 3 ? 1 : 0) - (a.lapses >= 3 ? 1 : 0);
        return hard != 0 ? hard : a.due.compareTo(b.due);
      });
    return due.take(limit).toList();
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
