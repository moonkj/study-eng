import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/grade_source.dart';
import 'package:todaye/data/pack_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/data/toeic.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/study_log.dart';
import 'package:todaye/domain/toeic_feedback.dart';

import '../support/fixed_fallback.dart';
import '../support/toeic_fixture.dart';

SavedData _saved({
  AppSettings settings = const AppSettings(),
  TodayProgress? today,
  List<MockResult> mocks = const [],
}) => SavedData(
  profile: LearnerProfile(overall: Level.fromStep(7), skills: {for (final s in Skill.values) s: Level.fromStep(7)}),
  contentStep: 7,
  onboarded: true,
  settings: settings,
  today: today,
  mocks: mocks,
);

ProviderContainer _container(AppStore store, {DateTime? now}) {
  final c = ProviderContainer(
    overrides: [
      storeProvider.overrideWithValue(store),
      clockProvider.overrideWithValue(() => now ?? DateTime(2026, 11, 22, 8)),
      fallbackPackProvider.overrideWithValue(fixedSamplePackFor),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('문항 모음 읽기', () {
    test('유형별로 읽고, 깨진 문항만 버린다', () {
      final b = toeicFixture;
      expect(b.readAloud.length, 3);
      expect(b.pictures.length, 3);
      expect(b.questions.single.questions.length, 3);
      expect(b.infoTables.single.table.rows.length, 2);
      expect(b.infoTables.single.table.subtitle, 'Grand Hotel, May 3');
      expect(b.opinions.map((o) => o.id), ['op-1']); // op-bad 는 버림
      expect(b.readAloud.first.tips, ['쉼표에서 잠깐 쉬어요.']);
      expect(b.readAloud.last.level, ToeicTier.ih);
      expect(b.usable, isTrue);
    });

    test('단계별 모범 답안·핵심 표현: 없는 단계는 바로 아래 단계로', () {
      final pic = toeicFixture.pictures.first;
      expect(pic.model.at(ToeicTier.basic), startsWith('This picture was taken in a cafe'));
      expect(pic.model.at(ToeicTier.ih), startsWith('This photo was taken at a busy cafe'));
      expect(pic.model.at(ToeicTier.al), pic.model.at(ToeicTier.ih)); // AL 없음 → IH
      expect(pic.keyPhrases.at(ToeicTier.al), ['This photo was taken at', 'sipping']);
      final op = toeicFixture.opinions.single;
      expect(op.model.at(ToeicTier.al), startsWith('I wholeheartedly'));
      final q = toeicFixture.questions.single;
      expect(q.models.at(ToeicTier.al), q.models.basic); // IH·AL 없음 → 기본
    });

    test('JSON 문자열도 읽고, 유형이 비면 쓸 수 없는 모음', () {
      expect(ToeicBank.parse(jsonEncode(toeicFixtureJson)).pictures.length, 3);
      expect(ToeicBank.parse('{"readAloud": []}').usable, isFalse);
    });
  });

  group('오늘의 세트', () {
    test('같은 날은 같은 세트, 묶음은 날마다 Q5-7 → Q8-10 → Q11 로 돌아간다', () {
      final d = DateTime(2026, 11, 22);
      final a = dailySetFor(toeicFixture, d, ToeicTarget.im3);
      final b = dailySetFor(toeicFixture, DateTime(2026, 11, 22, 20), ToeicTarget.im3);
      expect(a.readAloud.id, b.readAloud.id);
      expect(a.block, b.block);
      final blocks = [
        for (var i = 0; i < 3; i++) dailySetFor(toeicFixture, DateTime(2026, 11, 22 + i), ToeicTarget.im3).block,
      ];
      expect(blocks.toSet(), ToeicBlock.values.toSet());
      final s = dailySetFor(toeicFixture, d, ToeicTarget.im3);
      expect(switch (s.block) {
        ToeicBlock.respond => s.respond,
        ToeicBlock.info => s.info,
        ToeicBlock.opinion => s.opinion,
      }, isNotNull);
    });

    test('목표 단계 문항부터 고르고, 그 단계가 없으면 가까운 단계로', () {
      for (var i = 0; i < 6; i++) {
        final d = DateTime(2026, 11, 1 + i);
        expect(dailySetFor(toeicFixture, d, ToeicTarget.im3).readAloud.level, ToeicTier.basic);
        expect(dailySetFor(toeicFixture, d, ToeicTarget.ih).readAloud.id, 'ra-ih');
        // AL 문항이 없으면 IH 부터
        expect(dailySetFor(toeicFixture, d, ToeicTarget.al).picture.id, 'pic-ih');
      }
      // 표·질문은 기본 단계뿐: IH 목표여도 기본 문항을 쓴다
      expect(poolFor(toeicFixture.infoTables, (e) => e.level, ToeicTier.ih).single.id, 'info-1');
      expect(tierOrder(ToeicTier.al), [ToeicTier.al, ToeicTier.ih, ToeicTier.basic]);
    });

    test('모의고사 세트: 문장 읽기·사진은 서로 다른 2개', () {
      final m = mockSetFor(toeicFixture, DateTime(2026, 11, 22), ToeicTarget.im3);
      expect(m.readAloud.map((e) => e.id).toSet().length, 2);
      expect(m.pictures.map((e) => e.id).toSet().length, 2);
      expect(m.respond.id, 'q-1');
    });
  });

  group('목표 등급', () {
    test('점수 → 등급·단계·표현 난이도', () {
      expect(ToeicTarget.fromScore(null), ToeicTarget.im3);
      expect(ToeicTarget.fromScore(160).tier, ToeicTier.ih);
      expect(ToeicTarget.fromScore(110).contentStep, 5);
      expect(ToeicTarget.fromScore(180).contentStep, 11);
      expect(ToeicTarget.im3.range, '140-150');
      expect(ToeicTarget.al.next, isNull);
      expect(meetsTarget('IH', ToeicTarget.im3), isTrue);
      expect(meetsTarget('IM2', ToeicTarget.im3), isFalse);
      expect(meetsTarget('IM3', ToeicTarget.im3), isTrue);
    });

    test('목표를 바꾸면 표현·단어 난이도 단계도 옮기고 저장한다', () {
      final store = MemoryStore(_saved());
      final c = _container(store);
      c.read(studyProvider.notifier).setToeicTarget(ToeicTarget.ih);
      var s = c.read(studyProvider);
      expect(s.contentStep, 9);
      expect(s.toeicTarget, ToeicTarget.ih);
      expect(store.load()!.settings.toeicTarget, 160);
      c.read(studyProvider.notifier).setToeicTarget(ToeicTarget.im1);
      s = c.read(studyProvider);
      expect(s.contentStep, 5);
      expect(Level.fromStep(s.contentStep).label, 'A2.3');
    });

    test('팩 요청에 목표를 넣는다 (고른 경우에만)', () {
      final r = buildPackRequest(
        date: DateTime(2026, 11, 22),
        profile: defaultProfile(),
        contentStep: 7,
        learned: const {},
        cards: const {},
        toeicTarget: 'IH',
      );
      expect(r['toeicTarget'], 'IH');
      final none = buildPackRequest(
        date: DateTime(2026, 11, 22),
        profile: defaultProfile(),
        contentStep: 7,
        learned: const {},
        cards: const {},
      );
      expect(none.containsKey('toeicTarget'), isFalse);
    });

    test('모의고사가 목표에 닿으면 다음 목표를 제안하고, 올리거나 닫으면 사라진다', () {
      final c = _container(MemoryStore(_saved(settings: const AppSettings(toeicTarget: 140))));
      final n = c.read(studyProvider.notifier);
      n.recordMock(const MockResult(date: '2026-11-22', level: 'IM2', target: 'IM3', scores: [60]));
      expect(c.read(studyProvider).targetReached, isFalse);
      n.recordMock(const MockResult(date: '2026-11-22', level: 'IH', target: 'IM3', scores: [82]));
      expect(c.read(studyProvider).targetReached, isTrue);
      n.dismissTargetSuggestion();
      expect(c.read(studyProvider).targetReached, isFalse);
      n.recordMock(const MockResult(date: '2026-11-23', level: 'IM3', target: 'IM3', scores: [72]));
      expect(c.read(studyProvider).targetReached, isTrue);
      n.setToeicTarget(ToeicTarget.im3.next!);
      final s = c.read(studyProvider);
      expect(s.toeicTarget, ToeicTarget.ih);
      expect(s.contentStep, 9);
      expect(s.targetReached, isFalse); // IM3 은 새 목표 IH 에 못 미친다
    });
  });

  group('기기 피드백', () {
    test('핵심 표현 사용: 대소문자·문장부호 무시, ~ 자리는 아무 말', () {
      expect(usedPhrase('Well, in the FOREGROUND, a woman...', 'in the foreground'), isTrue);
      expect(usedPhrase("I've been meaning to call you", "I've been meaning to ~"), isTrue);
      expect(usedPhrase('It is not only cheap but also fast', 'not only ~ but also'), isTrue);
      expect(usedPhrase('foreground', 'in the foreground'), isFalse);
      expect(usedPhrases('I usually go because I like it', ['I usually', 'because', 'First']), [
        'I usually',
        'because',
      ]);
      expect(wordCount('  one two  three '), 3);
      expect(wordCount(''), 0);
    });

    test('대략의 점수: 말이 없으면 0, 분량과 핵심 표현을 채울수록 높다, 문장 읽기는 원문 일치', () {
      expect(offlineScore(type: ToeicTaskType.picture, transcript: '', limitSeconds: 30), 0);
      final short = offlineScore(
        type: ToeicTaskType.picture,
        transcript: 'A woman.',
        limitSeconds: 30,
        keyPhrases: ['cafe'],
      );
      final long = offlineScore(
        type: ToeicTaskType.picture,
        transcript: '${List.filled(30, 'word').join(' ')} cafe',
        limitSeconds: 30,
        keyPhrases: ['cafe'],
      );
      expect(short, lessThan(long));
      expect(long, 100);
      expect(
        offlineScore(
          type: ToeicTaskType.readAloud,
          transcript: 'hello world',
          limitSeconds: 45,
          reference: 'Hello world.',
        ),
        100,
      );
      expect(estimateLevel(72), 'IM3');
      expect(estimateLevel(95), 'AL');
      expect(estimateLevel(10), 'NL');
    });
  });

  group('채점 서버', () {
    test('주소: /dailyPack → /grade, 따로 주면 그 주소', () {
      expect(gradeUrlFor('https://x.net/dailyPack', ''), 'https://x.net/grade');
      expect(gradeUrlFor('https://x.net/dailyPack', 'https://y.net/g'), 'https://y.net/g');
      expect(gradeUrlFor('', ''), isNull);
      expect(gradeUrlFor('https://x.net/other', ''), isNull);
    });

    test('요청 형식과 응답 읽기 (targetMet 포함)', () async {
      late Map<String, Object?> sent;
      final source = RemoteGradeSource(
        url: 'https://x.net/grade',
        token: 't',
        client: MockClient((req) async {
          sent = (jsonDecode(req.body) as Map).cast();
          expect(req.headers['authorization'], 'Bearer t');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'score': 7,
                'maxScore': 10,
                'level': 'IM3',
                'summaryKo': '좋아요',
                'goodKo': ['표현이 자연스러워요'],
                'fixes': [
                  {'from': 'He go', 'to': 'He goes', 'whyKo': '3인칭 단수'},
                  {'bad': true},
                ],
                'improved': 'He goes to work.',
                'nextTipKo': '연결어를 써 보세요',
                'targetMet': true,
              }),
            ),
            200,
          );
        }),
      );
      final g = await source.grade(
        task: ToeicTaskType.picture,
        target: 'IM3',
        prompt: 'Describe',
        reference: 'model',
        transcript: ' He go to work ',
        seconds: 20,
        limitSeconds: 30,
      );
      expect(sent['task'], 'picture');
      expect(sent['target'], 'IM3');
      expect(sent['transcript'], 'He go to work');
      expect(sent['limitSeconds'], 30);
      expect(g.percent, 70);
      expect(g.fixes.single.to, 'He goes');
      expect(g.goodKo.single, '표현이 자연스러워요');
      expect(g.targetMet, isTrue);
      expect(g.nextTipKo, '연결어를 써 보세요');
    });

    test('실패하면 한국어 이유', () async {
      final source = RemoteGradeSource(
        url: 'https://x.net/grade',
        token: 't',
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      expect(
        () => source.grade(
          task: ToeicTaskType.opinion,
          target: 'IH',
          prompt: 'q',
          transcript: 'a',
          seconds: 1,
          limitSeconds: 60,
        ),
        throwsA(isA<PackFetchException>()),
      );
    });
  });

  group('저장', () {
    test('토스 결과·목표·모의고사 기록이 저장됐다가 그대로 읽힌다', () {
      final data = _saved(
        settings: const AppSettings(toeicTarget: 160, toeicSuggestDismissed: 'x'),
        today: const TodayProgress(
          date: '2026-11-22',
          toeic: {
            'ra-1': ToeicTaskRecord(type: ToeicTaskType.readAloud, score: 88, words: 12, seconds: 30, limit: 45),
            'q-1': ToeicTaskRecord(type: ToeicTaskType.respond, score: 70, graded: true),
          },
        ),
        mocks: const [
          MockResult(date: '2026-11-21', level: 'IM2', target: 'IM3', scores: [60, null, 70], graded: true),
        ],
      );
      final back = SavedData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, Object?>);
      expect(back.settings.toeicTarget, 160);
      expect(back.settings.target, ToeicTarget.ih);
      expect(back.settings.toeicSuggestDismissed, 'x');
      expect(back.today!.toeic['ra-1']!.score, 88);
      expect(back.today!.toeic['ra-1']!.limit, 45);
      expect(back.today!.toeic['q-1']!.graded, isTrue);
      expect(back.mocks.single.scores, [60, null, 70]);
      expect(back.mocks.single.level, 'IM2');
    });

    test('예전 형식(필드 없음)·이상한 값도 읽힌다', () {
      final old = _saved().toJson()
        ..['settings'] = {'voice': 'en-US', 'toeicTarget': 999}
        ..['today'] = {
          'date': '2026-11-22',
          'toeic': {
            'ok': {'type': 'opinion', 'score': 120},
            'bad': {'type': 'nope', 'score': 1},
          },
        }
        ..['mocks'] = [
          {'date': '2026-11-21', 'level': 'IH'},
          'broken',
        ];
      final back = SavedData.fromJson(jsonDecode(jsonEncode(old)) as Map<String, Object?>);
      expect(back.settings.toeicTarget, isNull);
      expect(back.settings.target, ToeicTarget.im3);
      expect(back.today!.toeic.keys, ['ok']);
      expect(back.today!.toeic['ok']!.score, 100);
      expect(back.mocks.single.level, 'IH');
      final none = SavedData.fromJson(jsonDecode(jsonEncode(_saved().toJson())) as Map<String, Object?>);
      expect(none.mocks, isEmpty);
      expect(none.settings.toeicTarget, isNull);
    });

    test('루틴을 끝내면 토스 점수가 말하기 평균이 된다 (따라 말하기 점수 대신)', () {
      final c = _container(MemoryStore(_saved()));
      final n = c.read(studyProvider.notifier);
      n.recordToeicTask('ra-1', const ToeicTaskRecord(type: ToeicTaskType.readAloud, score: 90));
      n.recordToeicTask('ra-1', const ToeicTaskRecord(type: ToeicTaskType.readAloud, score: 40)); // 낮은 재시도는 무시
      n.recordToeicTask('pic-1', const ToeicTaskRecord(type: ToeicTaskType.picture, score: 60));
      expect(c.read(studyProvider).toeicAverage, 75);
      expect(c.read(studyProvider).untouched, isFalse);
      for (final step in RoutineStep.values) {
        n.complete(step);
      }
      final s = c.read(studyProvider);
      expect(s.log[dateKey(s.now)]!.speakingAverage, 75);
      // 끝낸 뒤 다시 한 것은 연습: 기록을 바꾸지 않는다
      n.recordToeicTask('op-1', const ToeicTaskRecord(type: ToeicTaskType.opinion, score: 100));
      expect(c.read(studyProvider).today.toeic.containsKey('op-1'), isFalse);
    });
  });
}
