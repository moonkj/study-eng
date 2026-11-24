import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todaye/app/study_controller.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/domain/srs.dart';
import 'package:todaye/domain/study_log.dart';

import '../support/fixed_fallback.dart';

ProviderContainer containerAt(DateTime now, AppStore store) => ProviderContainer(
  overrides: [
    storeProvider.overrideWithValue(store),
    clockProvider.overrideWithValue(() => now),
    fallbackPackProvider.overrideWithValue(fixedSamplePackFor),
  ],
);

void main() {
  group('연속 학습일', () {
    final today = DateTime(2026, 11, 22);
    test('오늘까지 이어진 날을 센다', () {
      expect(computeStreak(['2026-11-20', '2026-11-21', '2026-11-22'], today), 3);
    });
    test('오늘 아직 안 했어도 어제까지 이어졌으면 유지된다', () {
      expect(computeStreak(['2026-11-20', '2026-11-21'], today), 2);
    });
    test('하루 빠지면 끊긴다', () {
      expect(computeStreak(['2026-11-19', '2026-11-20'], today), 0);
    });
    test('월이 바뀌어도 이어진다', () {
      expect(computeStreak(['2026-10-31', '2026-11-01'], DateTime(2026, 11, 1)), 2);
    });

    test('7일 연속마다 쉬는 날이 생기고, 하루 빠지면 자동으로 써서 기록을 지킨다', () {
      final week = [for (var d = 1; d <= 7; d++) dateKey(DateTime(2026, 11, d))];
      // 11/8 빠짐 → 쉬는 날 사용, 11/9 공부
      var info = computeStreakInfo([...week, '2026-11-09'], DateTime(2026, 11, 9));
      expect(info.days, 8);
      expect(info.restsLeft, 0);
      expect(info.restDays, {'2026-11-08'});
      // 쉬는 날이 없을 때 또 빠지면 끊긴다
      info = computeStreakInfo([...week, '2026-11-09', '2026-11-11'], DateTime(2026, 11, 11));
      expect(info.days, 1);
      // 오늘 아직 안 했으면 빠진 날로 치지 않는다
      info = computeStreakInfo(week, DateTime(2026, 11, 8));
      expect(info.days, 7);
      expect(info.restsLeft, 1);
    });
  });

  group('저장과 복원', () {
    test('앱을 다시 켜도 레벨, 진행 상황, 복습 카드가 그대로다', () {
      final store = MemoryStore();
      final day = DateTime(2026, 11, 22, 8);
      final c1 = containerAt(day, store);
      final ctl = c1.read(studyProvider.notifier);
      ctl.skipLevelTest();
      ctl.rateWord('w-actually', SelfRating.know);
      ctl.setExpressionKnown('exp-running-late', true);
      ctl.answerQuiz(0, 1);
      ctl.recordSpeaking(c1.read(studyProvider).pack.sentences.first, "Actually I think I'll take the buss today");
      c1.dispose();

      final c2 = containerAt(day.add(const Duration(hours: 3)), store);
      final s = c2.read(studyProvider);
      expect(s.onboarded, isTrue);
      expect(s.wordRatings['w-actually'], SelfRating.know);
      expect(s.expressionKnown['exp-running-late'], isTrue);
      expect(s.quizAnswers[0], 1);
      expect(s.speaking.values.single.missed, ['bus']);
      expect(s.cards['w-actually']!.due, DateTime(2026, 11, 29));
      c2.dispose();
    });

    test('날짜가 바뀌면 오늘 진행은 새로 시작하지만 기록은 남는다', () {
      final store = MemoryStore();
      final c1 = containerAt(DateTime(2026, 11, 22, 8), store);
      final ctl = c1.read(studyProvider.notifier);
      ctl.skipLevelTest();
      for (var i = 0; i < c1.read(studyProvider).pack.quiz.length; i++) {
        ctl.answerQuiz(i, c1.read(studyProvider).pack.quiz[i].answerIndex);
      }
      for (final step in RoutineStep.values) {
        ctl.complete(step);
      }
      final scoreAfter = c1.read(studyProvider).profile.overall.score;
      c1.dispose();

      final c2 = containerAt(DateTime(2026, 11, 23, 7), store);
      final s = c2.read(studyProvider);
      expect(s.done, isEmpty);
      expect(s.quizAnswers, isEmpty);
      expect(s.streakDays, 1);
      expect(s.yesterdayAccuracy, 1.0);
      expect(s.profile.overall.score, scoreAfter);
      expect(s.log.keys, ['2026-11-22']);
      c2.dispose();
    });

    test('SharedPreferences에 JSON으로 저장되고 다시 읽힌다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = containerAt(DateTime(2026, 11, 22), PrefsStore(prefs));
      c.read(studyProvider.notifier).skipLevelTest();
      c.read(studyProvider.notifier).rateWord('w-commute', SelfRating.confusing);
      await Future<void>.delayed(Duration.zero);
      final loaded = PrefsStore(prefs).load()!;
      expect(loaded.onboarded, isTrue);
      expect(loaded.today!.wordRatings['w-commute'], SelfRating.confusing);
      expect(loaded.cards['w-commute']!.stage, 1);
      c.dispose();
    });

    test('저장 데이터가 깨져 있으면 처음부터 시작한다', () async {
      SharedPreferences.setMockInitialValues({'todaye.v1': '{broken'});
      final prefs = await SharedPreferences.getInstance();
      expect(PrefsStore(prefs).load(), isNull);
      expect(prefs.getString('todaye.v1.corrupt'), '{broken');
      expect(prefs.getString('todaye.v1'), isNull);
    });
  });
}
