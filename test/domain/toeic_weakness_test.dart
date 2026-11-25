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

void main() {
  const log = {
    '2026-11-18': {'read_aloud': 80, 'picture': 70, 'info': 40},
    '2026-11-19': {'read_aloud': 82, 'picture': 72, 'respond': 75},
    '2026-11-20': {'read_aloud': 84, 'picture': 74, 'info': 44},
    '2026-11-21': {'read_aloud': 86, 'picture': 76, 'opinion': 70, 'respond': 77},
  };

  test('유형별 최근 평균: 루틴 점수와 모의고사(유형별 평균 한 번)를 함께 쓴다', () {
    final stats = typeStats(log, [
      const MockResult(
        date: '2026-11-21',
        level: 'IM1',
        target: 'IM3',
        scores: [90, 90, 70, 70, 60, 60, 60, 30, 40, 50, 66],
      ),
    ]);
    expect(stats[ToeicTaskType.info]!.average, closeTo((40 + 44 + 40) / 3, 0.01));
    expect(stats[ToeicTaskType.info]!.samples, 3);
    expect(stats[ToeicTaskType.opinion]!.samples, 2);
    expect(weakestType(stats), ToeicTaskType.info);
    expect(weakBlock(stats), ToeicBlock.info);
  });

  test('기록이 적거나 점수 차가 작으면 약점이라고 하지 않는다', () {
    expect(
      weakBlock(
        typeStats(const {
          '2026-11-20': {'info': 30},
        }, const []),
      ),
      isNull,
    );
    expect(
      weakBlock(
        typeStats(const {
          '2026-11-19': {'info': 60, 'respond': 62},
          '2026-11-20': {'info': 60, 'respond': 63},
        }, const []),
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

  test('날짜별 점수: 같은 날 같은 유형은 높은 점수만, 오래된 날은 지운다', () {
    var d = addDailyScore(const {}, '2026-11-22', ToeicTaskType.info, 50);
    d = addDailyScore(d, '2026-11-22', ToeicTaskType.info, 40);
    expect(d['2026-11-22']!['info'], 50);
    d = addDailyScore(d, '2026-11-23', ToeicTaskType.info, 60, keep: 1);
    expect(d.keys, ['2026-11-23']);
  });

  test('루틴 결과가 저장되고, 다음 날 세트에 약점 묶음이 들어간다', () {
    final saved = SavedData(
      profile: LearnerProfile(overall: Level.fromStep(7), skills: {for (final s in Skill.values) s: Level.fromStep(7)}),
      contentStep: 7,
      onboarded: true,
      toeicLog: log,
    );
    final back = SavedData.fromJson(saved.toJson());
    expect(back.toeicLog, log);

    // 2026-11-23 은 약점 날(홀수 날) 이고 원래 차례가 info 가 아닌 날을 찾는다
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

    c.read(studyProvider.notifier).recordToeicTask('x', const ToeicTaskRecord(type: ToeicTaskType.info, score: 90));
    final s = c.read(studyProvider);
    expect(s.toeicLog[s.today.date]!['info'], 90);
    // 오늘 점수가 높아도 오늘 세트는 그대로
    expect(c.read(toeicDailyProvider)!.block, ToeicBlock.info);
  });
}
