import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/sample_content.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/pack_check.dart';
import 'package:todaye/domain/pack_prep.dart';
import 'package:todaye/domain/study_log.dart';

void main() {
  final day = DateTime(2026, 11, 23);

  group('처음 1~3일 분량', () {
    test('1일차: 표현 2 · 단어 5 · 문장 5 · 고르는 문제 5 + 쓰기 1', () {
      final p = prepareDailyPack(samplePack(day), dayNumber: 1);
      expect(p.expressions.length, 2);
      expect(p.words.length, 5);
      expect(p.sentences.length, 7); // 단어 문장 5 + 표현 문장 2
      expect(p.quiz.where((q) => !q.isRecall).length, 5);
      expect(p.quiz.where((q) => q.isRecall).length, 1);
      // 빠진 표현·단어를 묻는 문제는 없다
      final ids = {...p.expressions.map((e) => e.id), ...p.words.map((w) => w.id)};
      expect(p.quiz.every((q) => ids.contains(q.itemId)), isTrue);
      // 문장은 남긴 단어를 쓰는 것, 표현 문장은 남긴 표현의 예문
      final words = p.words.map((w) => w.word).toSet();
      final highlights = p.expressions.map((e) => e.highlight).toSet();
      expect(p.sentences.every((s) => words.contains(s.focus) || highlights.contains(s.focus)), isTrue);
      // 남긴 표현마다 그 표현을 묻는 문제가 있다
      expect(p.expressions.every((e) => p.quiz.any((q) => q.itemId == e.id)), isTrue);
      expect(checkPack(p), isEmpty);
    });

    test('2일차 7개, 3일차 8개, 4일차부터 팩 그대로 (+쓰기 2)', () {
      expect(prepareDailyPack(samplePack(day), dayNumber: 2).words.length, 7);
      expect(prepareDailyPack(samplePack(day), dayNumber: 3).words.length, 8);
      final full = prepareDailyPack(samplePack(day), dayNumber: 4);
      expect(full.words.length, 10);
      expect(full.quiz.length, 12);
    });

    test('같은 입력이면 같은 팩 (저장된 문제 번호가 어긋나지 않게)', () {
      final a = prepareDailyPack(samplePack(day), dayNumber: 2);
      final b = prepareDailyPack(samplePack(day), dayNumber: 2);
      expect(a.quiz.map((q) => q.id), b.quiz.map((q) => q.id));
      expect(packIdOf(a), packIdOf(b));
    });

    test('학습 n일차는 오늘 이전에 끝낸 날만 센다', () {
      expect(dayNumberOf(const [], day), 1);
      expect(dayNumberOf(['2026-11-20', '2026-11-22'], day), 3);
      expect(dayNumberOf(['2026-11-22', '2026-11-23'], day), 2); // 오늘 끝내도 그대로
    });
  });

  group('첫 글자 단서 쓰기', () {
    test('고르는 문제로 묻지 않은 단어를 먼저, 예문에서 첫 글자만 남긴다', () {
      final p = prepareDailyPack(samplePack(day), dayNumber: 4);
      final recall = p.quiz.where((q) => q.isRecall).toList();
      expect(recall.map((q) => q.itemId), ['w-actually', 'w-traffic']);
      expect(recall.first.clue, "A_______, I'm a little tired.");
      expect(recall.first.prompt, '사실 나 조금 피곤해.');
    });

    test('여러 단어 표현은 단어마다 첫 글자, 예문에 그대로 없으면 만들지 않는다', () {
      final a2 = samplePackA2(day);
      final toGo = a2.words.firstWhere((w) => w.word == 'to go');
      expect(recallItemFor(toGo)!.clue, 'One coffee t_ g_, please.');
      final figureOut = samplePack(day).words.firstWhere((w) => w.word == 'figure out');
      expect(recallItemFor(figureOut), isNull); // "figure it out" 은 떨어져 있다
    });

    test('대소문자·공백·따옴표·문장부호 차이는 정답으로 본다', () {
      final q = recallItemFor(samplePack(day).words.first)!;
      expect(isRecallCorrect(q, '  ACTUALLY. '), isTrue);
      expect(isRecallCorrect(q, 'actualy'), isFalse);
      expect(isRecallCorrect(q, ''), isFalse);
    });
  });

  group('A2 기본 팩', () {
    test('A2 이하 단계는 A2 팩, B1 이상은 B1 팩', () {
      expect(samplePackFor(day, 4).topic, samplePackA2(day).topic);
      expect(samplePackFor(day, 5).topic, samplePackA2(day).topic);
      expect(samplePackFor(day, 6).topic, samplePack(day).topic);
    });

    test('A2 팩은 화면이 그릴 수 있는 팩이고 문제는 모두 오늘 항목을 다룬다', () {
      final p = samplePackA2(day);
      expect(checkPack(p), isEmpty);
      expect(p.words.length, 10);
      expect(p.quiz.length, 10);
      final ids = {...p.expressions.map((e) => e.id), ...p.words.map((w) => w.id)};
      expect(p.quiz.every((q) => ids.contains(q.itemId)), isTrue);
      expect(p.quiz.every((q) => q.answerIndex < q.choices.length), isTrue);
      // 쓰기 문제를 만들 수 있게 단어가 예문에 그대로 들어 있다
      expect(p.words.every((w) => recallItemFor(w) != null), isTrue);
    });

    test('서버 없이 진단에서 초급(A2)이 나오면 시작 전 기본 팩이 A2 팩으로 바뀐다', () {
      final c = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(MemoryStore(null)),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 8)),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(studyProvider).pack.topic, samplePack(day).topic);
      c.read(studyProvider.notifier).skipLevelTest(beginner: true);
      final s = c.read(studyProvider);
      expect(s.pack.topic, samplePackA2(day).topic);
      expect(s.pack.words.length, 5); // 1일차 분량
      expect(s.learned.keys, containsAll(s.pack.words.map((w) => w.id)));
    });
  });

  test('완료 기록에 퀴즈 맞힌 수·문항 수를 저장하고 다시 읽는다', () {
    const r = DayRecord(accuracy: 0.5, levelScore: 700, quizCorrect: 6, quizTotal: 12);
    final back = DayRecord.fromJson(r.toJson());
    expect((back.quizCorrect, back.quizTotal), (6, 12));
    final old = DayRecord.fromJson(const {'accuracy': 0.5, 'levelScore': 700});
    expect(old.quizCorrect, isNull);
  });
}
