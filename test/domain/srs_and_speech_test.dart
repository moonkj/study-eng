import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/domain/korean_pron_tips.dart';
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

    test('퀴즈를 맞히면 간격이 늘고, 틀리면 두 단계 내려간다', () {
      var card = ReviewCard.fresh('q', today);
      card = Srs.answer(card, correct: true, today: today);
      expect(card.stage, 0);
      final day2 = today.add(const Duration(days: 1));
      card = Srs.answer(card, correct: true, today: day2);
      expect(card.due, DateTime(2026, 11, 26)); // 3일 뒤
      final day5 = today.add(const Duration(days: 4));
      card = Srs.answer(card, correct: true, today: day5);
      expect(card.stage, 2);
      card = Srs.answer(card, correct: false, today: day5.add(const Duration(days: 7)));
      expect(card.stage, 0);
      expect(card.lapses, 1);
    });

    test('같은 날 다시 맞힌 것은 단계를 올리지 않는다 (방금 본 것이라서)', () {
      var card = Srs.rate(ReviewCard.fresh('w', today), SelfRating.know, today);
      expect(card.stage, 2);
      card = Srs.answer(card, correct: true, today: today.add(const Duration(hours: 1)));
      expect(card.stage, 2);
      expect(card.due, DateTime(2026, 11, 29));
    });

    test('세 번 이상 틀린 카드를 먼저 복습한다', () {
      final cards = [
        ReviewCard(itemId: 'old', stage: 1, due: DateTime(2026, 11, 1)),
        ReviewCard(itemId: 'hard', stage: 0, due: DateTime(2026, 11, 20), lapses: 3),
      ];
      expect(Srs.dueToday(cards, today).first.itemId, 'hard');
    });

    test('30일 단계에서 퀴즈로 맞히면 졸업하고, 90일·180일 뒤 유지 복습 후 끝난다', () {
      var card = ReviewCard(itemId: 'x', stage: 4, due: DateTime(2026, 11, 1));
      card = Srs.answer(card, correct: true, today: today);
      expect(card.graduated, isTrue);
      expect(card.due, DateTime(2026, 11, 22).add(const Duration(days: 90)));
      final d1 = card.due;
      // 유지 복습에서 자가 평가 '알아요'는 단계를 지키고, 퀴즈로 맞혀야 다음으로
      expect(Srs.rate(card, SelfRating.know, d1).stage, card.stage);
      card = Srs.answer(card, correct: true, today: d1);
      expect(card.due, d1.add(const Duration(days: 180)));
      card = Srs.answer(card, correct: true, today: card.due);
      expect(card.retired, isTrue);
      expect(card.isDue(today.add(const Duration(days: 2000))), isFalse);
    });

    test('자가 평가 \'알아요\'만으로는 졸업하지 않는다', () {
      var card = ReviewCard(itemId: 'x', stage: 4, due: DateTime(2026, 11, 1));
      card = Srs.rate(card, SelfRating.know, today);
      expect(card.stage, 4);
      expect(card.graduated, isFalse);
      expect(card.due, DateTime(2026, 11, 29)); // 퀴즈로 확인하도록 일주일 뒤
    });

    test('복습 카드: 몰라요는 두 단계, 헷갈려요는 한 단계 내린다', () {
      final card = ReviewCard(itemId: 'x', stage: 3, due: DateTime(2026, 11, 1));
      expect(Srs.rate(card, SelfRating.dontKnow, today).stage, 1);
      expect(Srs.rate(card, SelfRating.confusing, today).stage, 2);
      expect(Srs.rate(card, SelfRating.dontKnow, today).lapses, 1);
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
      expect(s.score, 79); // 기능어 a 는 비중 절반, 군말 1개 -3
      expect(s.missed, ['little']);
      expect(s.words.map((w) => w.word), ['Actually,', "I'm", 'a', 'little', 'tired.']);
    });

    test('명사 축약, 구어 축약, 숫자·시각을 같은 말로 본다', () {
      expect(scoreSpeech("My commute's way shorter now.", 'my commute is way shorter now').score, 100);
      expect(scoreSpeech("I've gotta go.", 'I have got to go').score, 100);
      expect(scoreSpeech('I usually take the 8:10 bus.', 'I usually take the eight ten bus').score, 100);
      expect(scoreSpeech("The meeting's at 3.", "the meeting's at three").score, 100);
      expect(scoreSpeech('It starts at 7:05.', 'it starts at seven oh five').score, 100);
    });

    test("'d 는 would/had, 's 는 is/has/소유격 모두 인정, 하이픈·시각 읽기도 같게", () {
      expect(scoreSpeech("I'd been waiting.", 'I had been waiting').score, 100);
      expect(scoreSpeech("He's been busy.", 'he has been busy').score, 100);
      expect(scoreSpeech("My sister's car is new.", 'my sisters car is new').score, greaterThanOrEqualTo(90));
      expect(scoreSpeech("It's a well-known place.", "it's a well known place").score, 100);
      expect(scoreSpeech("Here's the thing:", "here's the thing").score, 100);
      expect(scoreSpeech("Let's meet at 3:15.", "let's meet at a quarter past three").score, 100);
      expect(scoreSpeech("Let's meet at 8:00.", "let's meet at eight o'clock").score, 100);
      expect(scoreSpeech('Lunch is at 12:00.', 'lunch is at noon').score, 100);
    });

    test('이상한 인식 결과에도 예외 없이 채점한다', () {
      expect(scoreSpeech('See you at 3.', 'see you at quarter to 75').score, lessThan(100));
      expect(scoreSpeech('Call 3.', 'call 123456789012345678901234').score, lessThan(100));
      expect(scoreSpeech('Hi.', '').score, 0);
    });

    test('a·the·to 를 놓쳐도 크게 깎지 않고, 다르게 들린 단어 목록에서는 뺀다', () {
      final s = scoreSpeech('I need to grab a coffee.', 'I need grab coffee');
      expect(s.score, greaterThanOrEqualTo(80));
      expect(s.missed, isEmpty);
    });

    test('축약형과 풀어 쓴 형태를 같은 말로 본다', () {
      expect(scoreSpeech("I'll definitely try it.", 'I will definitely try it').score, 100);
      expect(scoreSpeech('I do not know.', "I don't know").score, 100);
      expect(scoreSpeech("Don't worry, I'll figure it out.", "don't worry I'll figure it out").missed, isEmpty);
    });

    test('아무것도 인식되지 않으면 0점', () {
      expect(scoreSpeech('Hello there.', '').score, 0);
    });
  });

  test('한국인 발음 요령: 철자로 흔한 실수를 고른다', () {
    expect(koreanPronTip('think'), contains('th'));
    expect(koreanPronTip('very'), contains("'v'"));
    expect(koreanPronTip('coffee'), contains("'f'"));
    expect(koreanPronTip('crowded,'), contains("'r'"));
    expect(koreanPronTips(['the', 'that', 'very']).length, 2);
    expect(koreanPronTip('walk'), isNot(contains("'l'"))); // 묵음 l
    expect(koreanPronTip('listen'), contains('소리 내지 않아요'));
    expect(koreanPronTip('car'), contains("끝의 'r'"));
    expect(koreanPronTip('dogs'), contains('즈'));
  });
}
