import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/app/routine_flow.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/grade_source.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/data/toeic.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/toeic_feedback.dart';
import 'package:todaye/domain/toeic_weakness.dart';

import '../support/toeic_fixture.dart';

/// 첫 시도 점수만 있는 기록 (Claude 채점, 다시 하지 않음)
ToeicLog firstOnly(Map<String, Map<String, int>> m) => {
  for (final d in m.entries)
    d.key: {for (final t in d.value.entries) t.key: ToeicDayScore(first: t.value, best: t.value)},
};

SavedData _saved({ToeicLog toeicLog = const {}}) => SavedData(
  profile: LearnerProfile(overall: Level.fromStep(7), skills: {for (final s in Skill.values) s: Level.fromStep(7)}),
  contentStep: 7,
  onboarded: true,
  toeicLog: toeicLog,
);

void main() {
  final log = firstOnly(const {
    '2026-11-18': {'read_aloud': 80, 'picture': 70, 'info': 40},
    '2026-11-19': {'read_aloud': 82, 'picture': 72, 'respond': 75},
    '2026-11-20': {'read_aloud': 84, 'picture': 74, 'info': 44},
    '2026-11-21': {'read_aloud': 86, 'picture': 76, 'opinion': 70, 'respond': 77},
  });

  test('유형별 최근 평균: 루틴 점수와 채점된 모의고사(유형별 평균 한 번)를 함께 쓴다', () {
    final stats = typeStats(log, [
      const MockResult(
        date: '2026-11-21',
        level: 'IM1',
        target: 'IM3',
        scores: [90, 90, 70, 70, 60, 60, 60, 30, 40, 50, 66],
        graded: true,
      ),
    ]);
    expect(stats[ToeicTaskType.info]!.average, closeTo((40 + 44 + 40) / 3, 0.01));
    expect(stats[ToeicTaskType.info]!.samples, 3);
    expect(stats[ToeicTaskType.opinion]!.samples, 2);
    expect(weakestType(stats), ToeicTaskType.info);
    expect(weakBlock(stats), ToeicBlock.info);
  });

  test('모의고사는 Claude 채점 문항만: 기기 점수 모의고사는 빼고, 새 기록은 원점수로 계산한다', () {
    // 기기 점수(graded=false)만 있는 예전 모의고사는 약점 통계에 안 들어간다
    final offline = typeStats(const {}, [
      const MockResult(
        date: '2026-11-21',
        level: 'IM3',
        target: 'IM3',
        scores: [90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90],
      ),
    ]);
    expect(offline, isEmpty);
    // 원점수: 채점 안 된 문항(null)은 빼고, Q11 은 5점 만점
    final graded = typeStats(const {}, [
      const MockResult(
        date: '2026-11-21',
        level: 'IM2~IM3',
        target: 'IM3',
        scores: [99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99],
        points: [3, 3, 2, null, 2, 2, 2, 1, 2, 3, 4],
        graded: true,
      ),
    ]);
    expect(graded[ToeicTaskType.picture]!.average, closeTo(67, 0.01)); // Q3 만 (2/3)
    expect(graded[ToeicTaskType.info]!.average, closeTo((33 + 67 + 100) / 3, 0.5));
    expect(graded[ToeicTaskType.opinion]!.average, 80); // 4/5
  });

  test('기록이 적거나 점수 차가 작으면 약점이라고 하지 않는다', () {
    expect(
      weakBlock(
        typeStats(
          firstOnly(const {
            '2026-11-20': {'info': 30},
          }),
          const [],
        ),
      ),
      isNull,
    );
    expect(
      weakBlock(
        typeStats(
          firstOnly(const {
            '2026-11-19': {'info': 60, 'respond': 62},
            '2026-11-20': {'info': 60, 'respond': 63},
          }),
          const [],
        ),
      ),
      isNull,
    );
  });

  test('before 날짜부터의 기록은 빼서, 오늘 하는 동안 약점이 바뀌지 않는다', () {
    final stats = typeStats(log, const [], before: '2026-11-20');
    expect(stats[ToeicTaskType.info]!.samples, 1);
    expect(weakBlock(stats), isNull);
  });

  test('약점 묶음은 이틀에 한 번 넣고, 나머지 날은 평소대로 돌아간다', () {
    final blocks = [for (var i = 0; i < 6; i++) dailySetFor(toeicFixture, DateTime(2026, 11, 22 + i), ToeicTarget.im3)];
    final focused = [
      for (var i = 0; i < 6; i++)
        dailySetFor(toeicFixture, DateTime(2026, 11, 22 + i), ToeicTarget.im3, focus: ToeicBlock.info),
    ];
    final infoDays = focused.where((s) => s.block == ToeicBlock.info).length;
    expect(infoDays, greaterThanOrEqualTo(3));
    for (var i = 0; i < 6; i++) {
      final s = focused[i];
      if (!s.focused) expect(s.block, blocks[i].block); // 약점 날이 아니면 원래 차례
      if (s.focused) expect(s.block, ToeicBlock.info);
    }
    expect(blocks.any((s) => s.focused), isFalse);
  });

  test('날짜별 점수: Claude 채점만, 같은 날은 첫 시도를 고정하고 다시 한 최고 점수는 따로, 오래된 날은 지운다', () {
    var d = addDailyScore(const {}, '2026-11-22', ToeicTaskType.info, 90, graded: false); // 기기 점수는 안 넣는다
    expect(d, isEmpty);
    d = addDailyScore(d, '2026-11-22', ToeicTaskType.info, 50, graded: true);
    d = addDailyScore(d, '2026-11-22', ToeicTaskType.info, 70, graded: true);
    d = addDailyScore(d, '2026-11-22', ToeicTaskType.info, 60, graded: true);
    expect(d['2026-11-22']!['info'], const ToeicDayScore(first: 50, best: 70));
    // 약점 통계는 첫 시도(50)로, 성장 표시는 50 → 70
    expect(typeStats(d, const [])[ToeicTaskType.info]!.average, 50);
    final g = latestRetryGrowth(d)!;
    expect((g.type, g.first, g.best), (ToeicTaskType.info, 50, 70));
    d = addDailyScore(d, '2026-11-23', ToeicTaskType.info, 60, graded: true, keep: 1);
    expect(d.keys, ['2026-11-23']);
    expect(latestRetryGrowth(d), isNull);
  });

  test('예전 형식 기록(숫자 하나)은 최고 점수로만 남기고 약점 계산에서 뺀다', () {
    final old = _saved().toJson()
      ..['toeicLog'] = {
        '2026-11-20': {'info': 30, 'respond': 80},
        '2026-11-21': {'info': 35, 'respond': 82, 'bad': 'x'},
      };
    final back = SavedData.fromJson(jsonDecode(jsonEncode(old)) as Map<String, Object?>);
    expect(back.toeicLog['2026-11-21'], {
      'info': const ToeicDayScore(best: 35),
      'respond': const ToeicDayScore(best: 82),
    });
    expect(typeStats(back.toeicLog, const []), isEmpty);
    // 그날 처음 채점된 시도가 들어오면 그때부터 첫 시도로 친다
    final d = addDailyScore(back.toeicLog, '2026-11-21', ToeicTaskType.info, 20, graded: true);
    expect(d['2026-11-21']!['info'], const ToeicDayScore(first: 20, best: 35));
  });

  test('루틴 결과가 저장되고, 다음 날 세트에 약점 묶음이 들어간다', () {
    final back = SavedData.fromJson(_saved(toeicLog: log).toJson());
    expect(back.toeicLog, log);

    // 약점 날(홀수 날) 이고 원래 차례가 info 가 아닌 날을 찾는다
    final day = [
      for (var i = 0; i < 6; i++) DateTime(2026, 11, 22 + i),
    ].firstWhere((d) => dailySetFor(toeicFixture, d, ToeicTarget.im3, focus: ToeicBlock.info).focused);
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(MemoryStore(back)),
        clockProvider.overrideWithValue(() => DateTime(day.year, day.month, day.day, 8)),
        toeicBankProvider.overrideWithValue(toeicFixture),
      ],
    );
    addTearDown(c.dispose);
    final set = c.read(toeicDailyProvider)!;
    expect(set.block, ToeicBlock.info);
    expect(set.focused, isTrue);

    final n = c.read(studyProvider.notifier);
    // 기기 점수는 오늘 결과에만, 유형별 기록에는 안 남는다
    n.recordToeicTask('x', const ToeicTaskRecord(type: ToeicTaskType.info, score: 95));
    var s = c.read(studyProvider);
    expect(s.today.toeic['x']!.score, 95);
    expect(s.toeicLog[s.today.date], isNull);
    // Claude 채점: 첫 시도 60, 다시 해서 90 → 오늘 결과는 높은 점수, 기록은 첫 시도·최고 따로
    n.recordToeicTask('x', const ToeicTaskRecord(type: ToeicTaskType.info, score: 60, graded: true));
    n.recordToeicTask('x', const ToeicTaskRecord(type: ToeicTaskType.info, score: 90, graded: true));
    s = c.read(studyProvider);
    expect(s.toeicLog[s.today.date]!['info'], const ToeicDayScore(first: 60, best: 90));
    expect(s.today.toeic['x']!.score, 95);
    // 오늘 점수가 바뀌어도 오늘 세트는 그대로
    expect(c.read(toeicDailyProvider)!.block, ToeicBlock.info);
  });
}
