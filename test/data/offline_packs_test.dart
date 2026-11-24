import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/data/models.dart';
import 'package:todaye/data/sample_content.dart';
import 'package:todaye/data/topic_map.dart';
import 'package:todaye/domain/pack_check.dart';
import 'package:todaye/domain/pack_prep.dart';

void main() {
  final day = DateTime(2026, 11, 23);
  const a2Step = 4;
  const b1Step = 7;
  final levels = {'A2': a2Step, 'B1': b1Step};

  // 레벨별 (주제 id, 팩)
  List<(String, DailyPack)> packsOf(int step) => [for (final p in offlinePacksFor(step)) (p.topicId, p.build(day))];
  final all = [for (final step in levels.values) ...packsOf(step)];

  test('레벨마다 7개 이상, 첫 팩은 원래 기본 팩', () {
    expect(offlinePacksFor(a2Step).length, greaterThanOrEqualTo(7));
    expect(offlinePacksFor(b1Step).length, greaterThanOrEqualTo(7));
    expect(samplePacksFor(a2Step).length, offlinePacksFor(a2Step).length);
    expect(packsOf(a2Step).first.$2.topic, samplePackA2(day).topic);
    expect(packsOf(b1Step).first.$2.topic, samplePack(day).topic);
  });

  for (final MapEntry(key: level, value: step) in levels.entries) {
    group('$level 팩', () {
      for (final (topicId, p) in packsOf(step)) {
        group(p.topic, () {
          test('검사 통과 · 10/10/10/10 · 표현 3개', () {
            expect(checkPack(p), isEmpty);
            expect(p.expressions.length, 3);
            expect(p.words.length, 10);
            expect(p.sentences.length, 10);
            expect(p.quiz.length, 10);
            expect(p.contentStep <= 5, level == 'A2');
          });

          test('주제 지도에 있는 상황', () {
            expect(topicSituationById(topicId), isNotNull, reason: topicId);
          });

          test('퀴즈는 이 팩의 표현·단어를 묻고, 표현마다 문제가 있다', () {
            final ids = {...p.expressions.map((e) => e.id), ...p.words.map((w) => w.id)};
            for (final q in p.quiz) {
              expect(ids, contains(q.itemId), reason: q.id);
              expect(kErrorTypes, contains(q.errorType), reason: q.id);
              expect(q.choices.toSet().length, q.choices.length, reason: '${q.id} 보기 중복');
              expect(q.choices.length, inInclusiveRange(3, 4), reason: q.id);
            }
            for (final e in p.expressions) {
              expect(p.quiz.any((q) => q.itemId == e.id), isTrue, reason: '${e.id} 문제 없음');
            }
          });

          test('표현: 강조 부분이 패턴에 있고 예문 2개·발음 요령이 있다', () {
            for (final e in p.expressions) {
              expect(e.pattern.toLowerCase(), contains(e.highlight.toLowerCase()), reason: e.id);
              expect(e.examples.length, 2, reason: e.id);
              expect(e.pronKo, isNotNull, reason: e.id);
              expect(e.linkTip, isNotNull, reason: e.id);
            }
          });

          test('단어마다 회상형 문제를 만들 수 있다', () {
            // 옛 기본 팩의 figure out 은 예문이 "figure it out" 이라 일부러 회상형이 없다 (pack_prep_test 참고)
            for (final w in p.words.where((w) => w.id != 'w-figure-out')) {
              expect(recallItemFor(w), isNotNull, reason: w.id);
            }
          });

          test('문장의 focus 는 이 팩 단어이고 문장에 들어 있다', () {
            final words = {for (final w in p.words) w.word};
            for (final s in p.sentences) {
              expect(words, contains(s.focus), reason: s.id);
              final en = s.en.toLowerCase();
              final f = s.focus.toLowerCase();
              // 옛 기본 팩의 'invite' → 'inviting' 처럼 끝 e 가 빠진 활용형도 받아 준다
              final stem = f.endsWith('e') ? f.substring(0, f.length - 1) : f;
              expect(en.contains(f) || en.contains(stem), isTrue, reason: s.id);
            }
          });

          test('시리즈 대화 4~6줄', () {
            final d = p.dialogue;
            expect(d, isNotNull);
            expect(d!.lines.length, inInclusiveRange(4, 6));
            expect(d.title, level == 'A2' ? a2SeriesTitle : b1SeriesTitle);
            final text = d.lines.map((l) => l.en.toLowerCase()).join(' ');
            for (final e in p.expressions) {
              expect(text, contains(e.highlight.toLowerCase()), reason: '${e.id} 가 대화에 없음');
            }
          });
        });
      }

      test('회차는 도는 순서대로 1..N, 주제·제목은 서로 다르다', () {
        final packs = packsOf(step);
        expect([for (final (_, p) in packs) p.dialogue!.episode], [for (var i = 1; i <= packs.length; i++) i]);
        expect({for (final (t, _) in packs) t}.length, packs.length);
        expect({for (final (_, p) in packs) p.topic}.length, packs.length);
      });

      test('14일 동안 모든 팩(7개 이상)이 나오고, 같은 날짜면 같은 팩', () {
        final topics = <String>{};
        for (var i = 0; i < 14; i++) {
          final d = DateTime(2026, 12, 1 + i);
          final a = samplePackFor(d, step);
          final b = samplePackFor(DateTime(d.year, d.month, d.day, 21, 30), step);
          expect(b.topic, a.topic);
          expect(a.date, d);
          topics.add(a.topic);
        }
        expect(topics.length, greaterThanOrEqualTo(7));
        expect(topics.length, offlinePacksFor(step).length);
      });
    });
  }

  test('기준일(2026-11-23)에는 원래 기본 팩, 다음 날은 다른 팩', () {
    expect(samplePackFor(day, a2Step).topic, samplePackA2(day).topic);
    expect(samplePackFor(day, b1Step).topic, samplePack(day).topic);
    final next = DateTime(2026, 11, 24);
    expect(samplePackFor(next, a2Step).topic, isNot(samplePackA2(next).topic));
    expect(samplePackFor(next, b1Step).topic, isNot(samplePack(next).topic));
    // 기준일 이전 날짜도 정상적으로 돈다
    expect(samplePackFor(DateTime(2026, 11, 16), b1Step).topic, samplePack(day).topic);
  });

  test('모든 팩의 id 는 서로 겹치지 않는다', () {
    final ids = <String>[
      for (final (_, p) in all) ...[
        ...p.expressions.map((e) => e.id),
        ...p.words.map((w) => w.id),
        ...p.sentences.map((s) => s.id),
        ...p.quiz.map((q) => q.id),
      ],
    ];
    final dup = <String>{};
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) dup.add(id);
    }
    expect(dup, isEmpty);
  });

  test('주제 지도: 7개 축, 상황 40~60개, id 고유', () {
    expect(topicMap.length, 7);
    expect(allTopicSituations.length, inInclusiveRange(40, 60));
    expect({for (final s in allTopicSituations) s.id}.length, allTopicSituations.length);
    for (final a in topicMap) {
      expect(topicAxisById(a.id), same(a));
      for (final s in a.situations) {
        expect(s.axisId, a.id);
        expect(s.canDo, isNotEmpty);
      }
    }
    expect(topicSituationById('없는-id'), isNull);
  });
}
