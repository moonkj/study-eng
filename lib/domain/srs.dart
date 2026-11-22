/// 간격 반복(SRS) 복습 스케줄.
library;

/// 단어 카드 자가 평가
enum SelfRating { dontKnow, confusing, know }

class ReviewCard {
  const ReviewCard({required this.itemId, required this.stage, required this.due, this.lapses = 0});

  /// 처음 볼 때 카드
  factory ReviewCard.fresh(String itemId, DateTime today) =>
      ReviewCard(itemId: itemId, stage: -1, due: _dateOnly(today));

  final String itemId;

  /// -1: 새 카드, 0..4: [Srs.intervals] 단계, 5: 졸업
  final int stage;
  final DateTime due;
  final int lapses;

  bool get graduated => stage >= Srs.intervals.length;

  bool isDue(DateTime today) => !graduated && !due.isAfter(_dateOnly(today));

  ReviewCard copyWith({int? stage, DateTime? due, int? lapses}) =>
      ReviewCard(itemId: itemId, stage: stage ?? this.stage, due: due ?? this.due, lapses: lapses ?? this.lapses);
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

  /// 퀴즈 결과: 맞히면 다음 단계, 틀리면 내일 다시
  static ReviewCard answer(ReviewCard card, {required bool correct, required DateTime today}) {
    final stage = correct ? (card.stage < 0 ? 0 : card.stage + 1) : 0;
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
      return card.copyWith(stage: intervals.length, due: base.add(const Duration(days: 3650)));
    }
    return card.copyWith(
      stage: stage,
      due: base.add(Duration(days: intervals[stage])),
      lapses: card.lapses + (lapse ? 1 : 0),
    );
  }

  /// 오늘 복습할 카드 (오래 밀린 순, 최대 [limit]개)
  static List<ReviewCard> dueToday(Iterable<ReviewCard> cards, DateTime today, {int limit = 5}) {
    final due = cards.where((c) => c.isDue(today)).toList()..sort((a, b) => a.due.compareTo(b.due));
    return due.take(limit).toList();
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
