import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/domain/speech_score.dart';
import 'package:todaye/domain/srs.dart';

void main() {
  final today = DateTime(2026, 11, 22, 8, 30);

  group('SRS', () {
    test('단어 버튼: 몰라요=1일, 헷갈려요=3일, 알아요=7일 뒤', () {
      final card = ReviewCard.fresh('w', today);
      expect(Srs.rate(card, SelfRating.dontKnow, today).due, DateTime(2026, 11, 23));
      expect(Srs.rate(card, SelfRating.confusing, today).due, DateTime(2026, 11, 25));
      expect(Srs.rate(card, SelfRating.know, today).due, DateTime(2026, 11, 29));
    });

    test('퀴즈를 맞히면 간격이 늘고, 틀리면 내일로 돌아간다', () {
      var card = ReviewCard.fresh('q', today);
      card = Srs.answer(card, correct: true, today: today);
      expect(card.stage, 0);
      card = Srs.answer(card, correct: true, today: today);
      expect(card.due, DateTime(2026, 11, 25));
      card = Srs.answer(card, correct: false, today: today);
      expect(card.due, DateTime(2026, 11, 23));
      expect(card.lapses, 1);
    });

    test('30일 단계 다음은 졸업', () {
      var card = ReviewCard(itemId: 'x', stage: 4, due: DateTime(2026, 11, 1));
      card = Srs.answer(card, correct: true, today: today);
      expect(card.graduated, isTrue);
      expect(card.isDue(today.add(const Duration(days: 365))), isFalse);
    });

    test('오늘 복습할 카드를 오래된 순으로 최대 5개 고른다', () {
      final cards = [
        for (var i = 0; i < 8; i++) ReviewCard(itemId: '$i', stage: 1, due: DateTime(2026, 11, 22 - i)),
        ReviewCard(itemId: 'future', stage: 1, due: DateTime(2026, 11, 30)),
      ];
      final due = Srs.dueToday(cards, today);
      expect(due.length, 5);
      expect(due.first.itemId, '7');
      expect(due.any((c) => c.itemId == 'future'), isFalse);
    });
  });

  group('말하기 채점', () {
    test('완벽하게 말하면 100점', () {
      final s = scoreSpeech("Actually, I'm a little tired.", "actually I'm a little tired");
      expect(s.score, 100);
      expect(s.missed, isEmpty);
    });

    test('다르게 들린 단어를 찾아낸다', () {
      final s = scoreSpeech("Actually, I'm a little tired.", "Actually I'm a liddle tired");
      expect(s.score, 80 - 3);
      expect(s.missed, ['little']);
      expect(s.words.map((w) => w.word), ['Actually,', "I'm", 'a', 'little', 'tired.']);
    });

    test('아무것도 인식되지 않으면 0점', () {
      expect(scoreSpeech('Hello there.', '').score, 0);
    });
  });
}
