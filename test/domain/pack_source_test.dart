import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/pack_source.dart';
import 'package:todaye/data/sample_content.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/srs.dart';

/// 서버(functions/src/fixture.ts)가 실제로 내보낸 JSON
Map<String, Object?> serverFixture() =>
    (jsonDecode(File('test/fixtures/server_pack.json').readAsStringSync()) as Map).cast<String, Object?>();

class FakeSource implements PackSource {
  FakeSource({this.fail = false});
  bool fail;
  final requests = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> fetch(Map<String, Object?> request) async {
    requests.add(request);
    if (fail) throw const PackFetchException('서버에 연결할 수 없어요.');
    final json = serverFixture();
    return {...json, 'date': request['date']};
  }
}

const profile = LearnerProfile(
  overall: Level(764),
  skills: {
    Skill.vocabulary: Level(980),
    Skill.grammar: Level(720),
    Skill.listening: Level(700),
    Skill.speaking: Level(430),
  },
);

SavedData onboarded({Map<String, LearnedItem> learned = const {}}) =>
    SavedData(profile: profile, contentStep: 8, onboarded: true, learned: learned);

/// 앱을 켠 것처럼 상태를 바로 만든다 (provider 는 처음 읽을 때 만들어진다)
ProviderContainer container(DateTime now, AppStore store, PackSource? source) {
  final c = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(store),
      clockProvider.overrideWithValue(() => now),
      packSourceProvider.overrideWithValue(source),
    ],
  );
  c.read(studyProvider);
  return c;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  final day = DateTime(2026, 11, 23, 7, 30);

  group('서버 계약', () {
    test('서버가 만든 JSON을 앱 모델로 읽는다', () {
      final learned = {
        'w-actually': const LearnedItem(
          id: 'w-actually',
          kind: 'word',
          text: 'actually',
          meaning: '사실은',
          firstSeen: '2026-11-20',
        ),
      };
      final pack = packFromJson(serverFixture(), learned: learned, today: day);
      expect(pack.fromClaude, isTrue);
      expect(pack.topic, '카페 · 아침');
      expect(pack.contentStep, Level.parse('B1.3')!.step);
      expect(pack.expressions.single.id, 'exp-could-i-get');
      expect(pack.expressions.single.compare!.$1, 'Give me ~');
      expect(pack.words.single.pronKo, '리필');
      expect(pack.quiz.first.itemId, 'exp-could-i-get');
      expect(pack.quiz.first.isReview, isFalse);
      expect(pack.quiz.last.reviewLabel, '3일 전에 배운 단어');
      expect(pack.quiz.last.itemId, 'w-actually');
    });
  });

  group('요청 만들기', () {
    test('레벨, 약점, 최근 배운 것, 오늘 복습할 것을 담는다', () {
      final learned = {
        'w-actually': const LearnedItem(
          id: 'w-actually',
          kind: 'word',
          text: 'actually',
          meaning: '사실은',
          firstSeen: '2026-11-20',
        ),
        'exp-old': const LearnedItem(
          id: 'exp-old',
          kind: 'expression',
          text: 'Long ago ~',
          meaning: '옛날',
          firstSeen: '2026-01-01',
        ),
      };
      final cards = {
        'w-actually': ReviewCard(itemId: 'w-actually', stage: 1, due: DateTime(2026, 11, 23)),
        'q-unrelated': ReviewCard(itemId: 'q-unrelated', stage: 0, due: DateTime(2026, 11, 20)),
        'exp-old': ReviewCard(itemId: 'exp-old', stage: 2, due: DateTime(2026, 12, 1)),
      };
      final r = buildPackRequest(date: day, profile: profile, contentStep: 8, learned: learned, cards: cards);
      expect(r['date'], '2026-11-23');
      expect(r['level'], 'B1.2');
      expect(r['contentLevel'], 'B1.3');
      expect(r['focusSkill'], 'speaking');
      expect(r['speakingSentences'], 12);
      expect((r['avoid'] as Map)['words'], ['actually']);
      expect((r['avoid'] as Map)['expressions'], isEmpty); // 60일 넘은 표현은 다시 나와도 된다
      expect((r['review'] as List).single, {'id': 'w-actually', 'kind': 'word', 'text': 'actually', 'meaning': '사실은'});
    });

    test('복습 라벨', () {
      LearnedItem item(String d) => LearnedItem(id: 'x', kind: 'expression', text: '', meaning: '', firstSeen: d);
      expect(reviewLabelFor(item('2026-11-22'), day), '어제 배운 표현');
      expect(reviewLabelFor(item('2026-11-16'), day), '1주 전에 배운 표현');
      expect(reviewLabelFor(item('2026-11-18'), day), '5일 전에 배운 표현');
    });
  });

  group('맞춤 팩 받기', () {
    test('진단을 마쳤고 오늘 팩이 없으면 받아오고, 저장해 두고, 다시 열면 또 받지 않는다', () async {
      final store = MemoryStore(onboarded());
      final source = FakeSource();
      final c1 = container(day, store, source);
      expect(c1.read(studyProvider).packLoading, isTrue);
      await settle();
      final s = c1.read(studyProvider);
      expect(s.packLoading, isFalse);
      expect(s.pack.fromClaude, isTrue);
      expect(s.pack.topic, '카페 · 아침');
      expect(s.learned.keys, containsAll(['exp-could-i-get', 'w-refill']));
      expect(source.requests.single['contentLevel'], 'B1.3');
      c1.dispose();

      final c2 = container(day.add(const Duration(hours: 2)), store, source);
      expect(c2.read(studyProvider).pack.fromClaude, isTrue);
      expect(c2.read(studyProvider).packLoading, isFalse);
      await settle();
      expect(source.requests.length, 1);
      c2.dispose();
    });

    test('서버가 실패하면 기본 팩으로 진행하고 이유를 알려준다. 다시 시도할 수 있다', () async {
      final source = FakeSource(fail: true);
      final c = container(day, MemoryStore(onboarded()), source);
      await settle();
      var s = c.read(studyProvider);
      expect(s.pack.fromClaude, isFalse);
      expect(s.pack.topic, samplePack(day).topic);
      expect(s.packError, '서버에 연결할 수 없어요.');

      source.fail = false;
      await c.read(studyProvider.notifier).loadTodayPack();
      s = c.read(studyProvider);
      expect(s.pack.fromClaude, isTrue);
      expect(s.packError, isNull);
      c.dispose();
    });

    test('서버가 설정되지 않았으면 기다리지 않고 기본 팩으로 시작한다', () {
      final c = container(day, MemoryStore(onboarded()), null);
      expect(c.read(studyProvider).packLoading, isFalse);
      expect(c.read(studyProvider).pack.fromClaude, isFalse);
      c.dispose();
    });

    test('퀴즈를 틀리면 그 문제가 다루는 표현의 복습이 내일로 당겨진다', () async {
      final c = container(day, MemoryStore(onboarded()), FakeSource());
      await settle();
      final ctl = c.read(studyProvider.notifier);
      ctl.setExpressionKnown('exp-could-i-get', true); // 7일 뒤
      expect(c.read(studyProvider).cards['exp-could-i-get']!.due, DateTime(2026, 11, 30));
      ctl.answerQuiz(0, 2); // 오답
      expect(c.read(studyProvider).cards['exp-could-i-get']!.due, DateTime(2026, 11, 24));
      c.dispose();
    });

    test('루틴을 끝내면 내일 팩을 미리 받아 두고, 다음 날엔 바로 쓴다', () async {
      final store = MemoryStore(onboarded());
      final source = FakeSource();
      final c1 = container(day, store, source);
      await settle();
      final ctl = c1.read(studyProvider.notifier);
      for (final step in RoutineStep.values) {
        ctl.complete(step);
      }
      await settle();
      expect(source.requests.length, 2);
      expect(source.requests.last['date'], '2026-11-24');
      c1.dispose();

      final c2 = container(DateTime(2026, 11, 24, 7), store, source);
      final s = c2.read(studyProvider);
      expect(s.packLoading, isFalse);
      expect(s.pack.fromClaude, isTrue);
      expect(s.packs.keys, ['2026-11-24']); // 지난 팩은 정리
      await settle();
      expect(source.requests.length, 2);
      c2.dispose();
    });
  });

  group('RemotePackSource', () {
    test('토큰을 보내고 응답을 읽는다', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return http.Response.bytes(utf8.encode(jsonEncode(serverFixture())), 200);
      });
      final src = RemotePackSource(url: 'https://example.test/dailyPack', token: 'tok', client: client);
      final json = await src.fetch({'date': '2026-11-23'});
      expect(sent.headers['authorization'], 'Bearer tok');
      expect(json['topic'], '카페 · 아침');
    });

    test('401이면 토큰 안내 메시지', () async {
      final src = RemotePackSource(
        url: 'https://example.test/dailyPack',
        token: 'bad',
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      expect(
        () => src.fetch({}),
        throwsA(isA<PackFetchException>().having((e) => e.message, 'message', contains('토큰'))),
      );
    });
  });
}
