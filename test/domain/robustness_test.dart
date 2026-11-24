import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/pack_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/srs.dart';
import 'package:todaye/domain/study_log.dart';

import 'pack_source_test.dart' show serverFixture, profile;
import '../support/fixed_fallback.dart';

/// 응답 시점을 테스트가 정하는 서버
class ControlledSource implements PackSource {
  final pending = <(Map<String, Object?>, Completer<Map<String, Object?>>)>[];

  @override
  Future<Map<String, Object?>> fetch(Map<String, Object?> request) {
    final c = Completer<Map<String, Object?>>();
    pending.add((request, c));
    return c.future;
  }

  void reply(int i, {String topic = '카페 · 아침'}) =>
      pending[i].$2.complete({...serverFixture(), 'date': pending[i].$1['date'], 'topic': topic});
}

SavedData onboarded({Map<String, Map<String, Object?>> packs = const {}}) =>
    SavedData(profile: profile, contentStep: 8, onboarded: true, packs: packs);

void main() {
  final day = DateTime(2026, 11, 23, 23, 50);

  test('학습일은 새벽 4시에 바뀐다', () {
    expect(studyDay(DateTime(2026, 11, 24, 1, 30)), DateTime(2026, 11, 23));
    expect(studyDay(DateTime(2026, 11, 24, 4, 0)), DateTime(2026, 11, 24));
  });

  test('새벽 4시를 넘기면 오늘 기준으로 새로 고친다', () {
    var now = day;
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    final ctl = c.read(studyProvider.notifier);
    ctl.rateWord('w-actually', SelfRating.know);
    expect(c.read(studyProvider).today.date, '2026-11-23');

    ctl.refreshIfNewDay(); // 같은 날이면 그대로
    expect(c.read(studyProvider).wordRatings, isNotEmpty);

    now = DateTime(2026, 11, 24, 0, 1); // 자정 직후는 아직 같은 학습일
    ctl.refreshIfNewDay();
    expect(c.read(studyProvider).wordRatings, isNotEmpty);

    now = DateTime(2026, 11, 24, 4, 1);
    ctl.refreshIfNewDay(); // 루틴 중이면 진행을 지우지 않고 미룬다
    expect(c.read(studyProvider).wordRatings, isNotEmpty);
    ctl.refreshIfNewDay(fromHome: true); // 홈으로 돌아오면 새로 고친다
    final s = c.read(studyProvider);
    expect(s.today.date, '2026-11-24');
    // 끝내지 못한 어제 루틴은 오늘 이어서 한다 (어제 팩·진행 그대로)
    expect(s.today.carriedFrom, '2026-11-23');
    expect(s.wordRatings, isNotEmpty);
    expect(s.cards['w-actually'], isNotNull); // 복습 카드는 남는다
    c.dispose();
  });

  test('저장된 팩이 깨져 있어도 앱이 멈추지 않고 기본 팩으로 시작한다', () {
    final store = MemoryStore(
      onboarded(
        packs: {
          '2026-11-23': {'date': '2026-11-23', 'topic': 'x', 'expressions': 'broken'},
        },
      ),
    );
    final c = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store), clockProvider.overrideWithValue(() => day)],
    );
    final s = c.read(studyProvider);
    expect(s.pack.fromClaude, isFalse);
    expect(s.packs, isEmpty);
    c.dispose();
  });

  test('팩 요청이 겹치면 최신 요청만 반영한다 (재진단 직후 옛 응답이 덮어쓰지 않게)', () async {
    final source = ControlledSource();
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
        packSourceProvider.overrideWithValue(source),
      ],
    );
    c.read(studyProvider);
    await Future<void>.delayed(Duration.zero);
    expect(source.pending.length, 1); // 앱 시작 시 요청

    c.read(studyProvider.notifier).applyLevelTest(defaultProfile(step: 4));
    expect(source.pending.length, 2);
    expect(source.pending[1].$1['level'], 'A2.2');

    source.reply(1, topic: '새 레벨 팩');
    await Future<void>.delayed(Duration.zero);
    source.reply(0, topic: '옛 레벨 팩');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(studyProvider).pack.topic, '새 레벨 팩');
    c.dispose();
  });

  test('기다리지 않고 기본 팩으로 시작하면 늦게 온 응답은 오늘 팩을 바꾸지 않는다', () async {
    final source = ControlledSource();
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
        packSourceProvider.overrideWithValue(source),
      ],
    );
    c.read(studyProvider);
    await Future<void>.delayed(Duration.zero);
    final ctl = c.read(studyProvider.notifier);
    ctl.startWithFallback();
    var s = c.read(studyProvider);
    expect(s.packLoading, isFalse);
    expect(s.learned.keys, contains('w-actually')); // 기본 팩도 배운 항목으로 등록

    source.reply(0);
    await Future<void>.delayed(Duration.zero);
    s = c.read(studyProvider);
    expect(s.pack.fromClaude, isFalse);
    c.dispose();
  });

  test('재진단하면 이전 레벨로 미리 받은 내일 팩을 버린다', () {
    final store = MemoryStore(
      onboarded(
        packs: {
          '2026-11-24': {...serverFixture(), 'date': '2026-11-24'},
        },
      ),
    );
    final c = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store), clockProvider.overrideWithValue(() => day)],
    );
    c.read(studyProvider.notifier).applyLevelTest(defaultProfile());
    expect(c.read(studyProvider).packs, isEmpty);
    c.dispose();
  });

  test('저장 데이터의 한 부분이 깨져도 레벨과 기록은 살아남는다', () {
    final json = SavedData(
      profile: profile,
      contentStep: 7,
      onboarded: true,
      log: {'2026-11-22': const DayRecord(accuracy: 0.9, levelScore: 770)},
    ).toJson();
    json['cards'] = 'broken';
    json['learned'] = 42;
    final loaded = SavedData.fromJson(json);
    expect(loaded.profile.overall, const Level(764));
    expect(loaded.log.keys, ['2026-11-22']);
    expect(loaded.cards, isEmpty);
    expect(loaded.learned, isEmpty);
  });

  test('최고 연속 학습일', () {
    expect(computeLongestStreak([]), 0);
    expect(computeLongestStreak(['2026-11-01', '2026-11-02', '2026-11-03', '2026-11-05', '2026-11-06']), 3);
    expect(computeLongestStreak(['2026-10-30', '2026-10-31', '2026-11-01']), 3);
  });

  test('복습 세션: 오늘 복습할 배운 항목만 보여주고, 평가하면 다음 복습일이 정해진다', () {
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
      ],
    );
    final ctl = c.read(studyProvider.notifier);
    ctl.rateWord('w-actually', SelfRating.dontKnow); // 내일 복습
    expect(ctl.dueReviews(), isEmpty);
    final saved = c.read(studyProvider).toSaved();
    c.dispose();

    final next = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(saved)),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 24, 8)),
      ],
    );
    final ctl2 = next.read(studyProvider.notifier);
    // 오늘 퀴즈에 나오는 항목은 퀴즈를 끝낸 뒤 복습에 나온다 (기본 팩을 다시 하는 날이라 같은 단어가 퀴즈에 있다)
    ctl2.complete(RoutineStep.quiz);
    expect(ctl2.dueReviews().map((i) => i.text), ['actually']);
    ctl2.reviewCard('w-actually', SelfRating.know);
    // 복습 카드의 '알았어요'는 한 단계씩 오른다 (내일 → 3일 뒤)
    expect(next.read(studyProvider).cards['w-actually']!.due, DateTime(2026, 11, 27));
    expect(ctl2.dueReviews(), isEmpty);
    next.dispose();
  });

  test('소리 내기 어려운 모드: 진행은 되지만 말하기 평균에는 넣지 않는다', () {
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
      ],
    );
    final ctl = c.read(studyProvider.notifier);
    final sentences = c.read(studyProvider).pack.sentences;
    ctl.recordSilent(sentences[0]);
    ctl.recordSpeaking(sentences[1], sentences[1].en);
    final s = c.read(studyProvider);
    expect(s.spokenCount, 2);
    expect(s.speaking.length, 1);
    expect(s.speakingAverage, 100);
    c.dispose();
  });

  test('같은 평가를 여러 번 누르거나 바꿔도 복습 단계가 계속 오르지 않는다', () {
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
      ],
    );
    final ctl = c.read(studyProvider.notifier);
    final id = c.read(studyProvider).pack.expressions.first.id;
    ctl.setExpressionKnown(id, true);
    final once = c.read(studyProvider).cards[id]!;
    ctl.setExpressionKnown(id, true);
    ctl.setExpressionKnown(id, false);
    ctl.setExpressionKnown(id, true);
    final after = c.read(studyProvider).cards[id]!;
    expect(after.stage, once.stage);
    expect(after.due, once.due);

    ctl.rateWord('w-actually', SelfRating.know);
    final w = c.read(studyProvider).cards['w-actually']!;
    ctl.rateWord('w-actually', SelfRating.dontKnow);
    ctl.rateWord('w-actually', SelfRating.know);
    expect(c.read(studyProvider).cards['w-actually']!.stage, w.stage);
    c.dispose();
  });

  test('단어 평가 되돌리기는 원래 카드로 돌아가고, 단어 단계를 끝낸 뒤에는 무시한다', () {
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
      ],
    );
    final ctl = c.read(studyProvider.notifier);
    ctl.rateWord('w-actually', SelfRating.know);
    ctl.undoWordRating('w-actually');
    var s = c.read(studyProvider);
    expect(s.cards.containsKey('w-actually'), isFalse); // 원래 없던 카드
    expect(s.wordRatings, isEmpty);

    ctl.rateWord('w-actually', SelfRating.know);
    ctl.complete(RoutineStep.words);
    ctl.undoWordRating('w-actually');
    s = c.read(studyProvider);
    expect(s.wordRatings['w-actually'], SelfRating.know);
    c.dispose();
  });

  test('오늘 진행이 다른 팩에 대한 것이면 비우고, 퀴즈 번호가 넘쳐도 멈추지 않는다', () {
    final saved = SavedData(
      profile: profile,
      contentStep: 8,
      onboarded: true,
      today: const TodayProgress(date: '2026-11-23', packId: 'other-pack', quizAnswers: {0: 1, 99: 0}),
    );
    final c = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(MemoryStore(saved)), clockProvider.overrideWithValue(() => day)],
    );
    final s = c.read(studyProvider);
    expect(s.quizAnswers, isEmpty);
    expect(s.today.packId, packIdOf(s.pack));
    c.dispose();

    final legacy = SavedData(
      profile: profile,
      contentStep: 8,
      onboarded: true,
      today: const TodayProgress(date: '2026-11-23', quizAnswers: {99: 0}),
    );
    final c2 = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(MemoryStore(legacy)), clockProvider.overrideWithValue(() => day)],
    );
    expect(c2.read(studyProvider).quizCorrect, 0);
    c2.dispose();
  });

  test('마지막 평가일이 저장되어 다시 켜도 같은 날 재정답으로 단계가 오르지 않는다', () {
    final card = ReviewCard(itemId: 'x', stage: 1, due: DateTime(2026, 11, 26), lapses: 3, lastReviewed: day);
    final back = cardFromJson('x', cardToJson(card));
    expect(back.lastReviewed, DateTime(2026, 11, 23));
    expect(back.lapses, 3);
  });

  test('오늘 팩을 Claude 로 만드는 것은 재시도·재진단 포함 하루 4번까지', () async {
    final source = ControlledSource();
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
        packSourceProvider.overrideWithValue(source),
      ],
    );
    c.read(studyProvider);
    await Future<void>.delayed(Duration.zero);
    final ctl = c.read(studyProvider.notifier);
    for (var i = 0; i < 4; i++) {
      ctl.applyLevelTest(defaultProfile(step: 4 + i));
    }
    expect(source.pending.length, 4); // 시작 1 + 재진단 3, 다섯 번째부터는 기본 팩
    expect(c.read(studyProvider).packLoading, isFalse);
    c.dispose();
  });

  test('끝낸 단계는 다시 평가해도 복습 일정이 바뀌지 않고, 속으로 따라 하기는 받은 점수를 지우지 않는다', () {
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
      ],
    );
    final ctl = c.read(studyProvider.notifier);
    ctl.rateWord('w-actually', SelfRating.dontKnow);
    ctl.complete(RoutineStep.words);
    final card = c.read(studyProvider).cards['w-actually'];
    ctl.rateWord('w-actually', SelfRating.know);
    expect(c.read(studyProvider).cards['w-actually']!.stage, card!.stage);

    final sentence = c.read(studyProvider).pack.sentences.first;
    ctl.recordSpeaking(sentence, sentence.en);
    ctl.recordSilent(sentence);
    expect(c.read(studyProvider).speakingAverage, 100);
    c.dispose();
  });

  test('예전·깨진 저장 데이터: 기록은 하루씩, 날짜 키 검사, 오늘 진행은 빠진 필드를 기본값으로', () {
    final json = SavedData(profile: profile, contentStep: 7, onboarded: true).toJson();
    json['log'] = {
      '2026-11-21': {'accuracy': 'old-format'},
      '2026-11-22': {'accuracy': 0.8, 'levelScore': 760},
      'not-a-date': {'accuracy': 0.8, 'levelScore': 760},
    };
    json['today'] = {
      'date': '2026-11-23',
      'done': ['words'],
    };
    final loaded = SavedData.fromJson(json);
    expect(loaded.log.keys, ['2026-11-22']);
    expect(loaded.today!.done, {'words'});
    expect(loaded.today!.wordRatings, isEmpty);
    // 앱도 이 데이터로 문제없이 시작한다
    final c = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(MemoryStore(loaded)), clockProvider.overrideWithValue(() => day)],
    );
    expect(c.read(studyProvider).streakDays, 1);
    c.dispose();
  });

  test('서버에 보내는 피할 단어 목록은 최근에 배운 것부터 400개', () {
    final learned = {
      for (var i = 0; i < 500; i++)
        'w-$i': LearnedItem(id: 'w-$i', kind: 'word', text: 'word$i', meaning: '뜻', firstSeen: '2026-10-01'),
      'w-new': const LearnedItem(id: 'w-new', kind: 'word', text: 'newest', meaning: '뜻', firstSeen: '2026-11-22'),
    };
    final req = buildPackRequest(date: day, profile: profile, contentStep: 8, learned: learned, cards: const {});
    final words = ((req['avoid'] as Map)['words'] as List);
    expect(words.length, 400);
    expect(words.first, 'newest');
  });

  test('이미 배운 기본 팩을 다시 하는 날: 복습 일정·레벨은 그대로, 기록만 남는다', () {
    final c1 = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
        fallbackPackProvider.overrideWithValue(fixedSamplePackFor),
      ],
    );
    final ctl1 = c1.read(studyProvider.notifier);
    ctl1.rateWord('w-actually', SelfRating.know);
    for (final step in RoutineStep.values) {
      ctl1.complete(step); // 끝낸 날이라 다음 날 이어서 하지 않는다
    }
    final saved = c1.read(studyProvider).toSaved();
    final stage = saved.cards['w-actually']!.stage;
    c1.dispose();

    final next = DateTime(2026, 11, 24, 9);
    final c2 = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(saved)),
        clockProvider.overrideWithValue(() => next),
        fallbackPackProvider.overrideWithValue(fixedSamplePackFor),
      ],
    );
    final s = c2.read(studyProvider);
    expect(s.isRepeatPack, isTrue);
    final ctl = c2.read(studyProvider.notifier);
    ctl.rateWord('w-actually', SelfRating.know);
    expect(c2.read(studyProvider).cards['w-actually']!.stage, stage);
    for (final step in RoutineStep.values) {
      ctl.complete(step);
    }
    final after = c2.read(studyProvider);
    expect(after.profile.overall, s.profile.overall);
    expect(after.log.containsKey('2026-11-24'), isTrue);
    c2.dispose();
  });

  test('저장할 때 완전히 익힌 카드와 오래된 배운 항목은 정리한다', () {
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(onboarded())),
        clockProvider.overrideWithValue(() => day),
      ],
    );
    final s = c
        .read(studyProvider)
        .copyWith(
          cards: {
            'w-old': ReviewCard(itemId: 'w-old', stage: Srs.retiredStage, due: DateTime(2036, 1, 1)),
            'w-keep': ReviewCard(itemId: 'w-keep', stage: 2, due: DateTime(2026, 12, 1)),
          },
          learned: {
            'w-old': const LearnedItem(id: 'w-old', kind: 'word', text: 'old', meaning: '뜻', firstSeen: '2025-01-01'),
            'w-keep': const LearnedItem(
              id: 'w-keep',
              kind: 'word',
              text: 'keep',
              meaning: '뜻',
              firstSeen: '2025-01-01',
            ),
            'w-recent': const LearnedItem(
              id: 'w-recent',
              kind: 'word',
              text: 'recent',
              meaning: '뜻',
              firstSeen: '2026-11-01',
            ),
          },
        );
    final saved = s.toSaved();
    expect(saved.cards.keys, ['w-keep']);
    expect(saved.learned.keys.toSet(), {'w-keep', 'w-recent'});
    c.dispose();
  });
}
