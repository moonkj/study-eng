import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/sample_content.dart';
import '../data/store.dart';
import '../domain/daily_adjuster.dart';
import '../domain/level.dart';
import '../domain/speech_score.dart';
import '../domain/srs.dart';
import '../domain/study_log.dart';

/// 오늘의 루틴 4단계
enum RoutineStep { expressions, words, speaking, quiz }

/// 테스트에서 날짜를 고정할 수 있도록 시계를 주입한다.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 오늘의 학습 팩을 만든다. (3단계에서 Claude 생성 팩으로 교체)
final packBuilderProvider = Provider<DailyPack Function(DateTime)>((ref) => samplePack);

class StudyState {
  StudyState({
    required this.now,
    required this.pack,
    required this.profile,
    required this.contentStep,
    required this.onboarded,
    required this.log,
    required this.cards,
    required this.today,
    required this.lastAdjustmentReasons,
  });

  final DateTime now;
  final DailyPack pack;
  final LearnerProfile profile;
  final int contentStep;
  final bool onboarded;
  final Map<String, DayRecord> log;
  final Map<String, ReviewCard> cards;
  final TodayProgress today;
  final List<String> lastAdjustmentReasons;

  Set<RoutineStep> get done => {for (final n in today.done) RoutineStep.values.byName(n)};
  Map<String, bool> get expressionKnown => today.expressionKnown;
  Map<String, SelfRating> get wordRatings => today.wordRatings;
  Map<int, int> get quizAnswers => today.quizAnswers;
  int? get todayLevelDelta => today.levelDelta;

  /// 오늘 말한 문장의 채점 결과 (저장된 인식 문장으로 다시 계산)
  late final Map<String, SpeechScore> speaking = {
    for (final s in pack.sentences)
      if (today.spoken.containsKey(s.id)) s.id: scoreSpeech(s.en, today.spoken[s.id]!),
  };

  int get streakDays => computeStreak(log.keys, now);

  /// 이번 달에 루틴을 끝낸 날짜(일)
  Set<int> get studiedDays => {
    for (final k in log.keys)
      if (parseDateKey(k).year == now.year && parseDateKey(k).month == now.month) parseDateKey(k).day,
  };

  double? get yesterdayAccuracy => previousRecord(log, now)?.accuracy;

  bool get allDone => done.length == RoutineStep.values.length;

  /// 지금 이어서 할 단계
  RoutineStep? get current {
    for (final s in RoutineStep.values) {
      if (!done.contains(s)) return s;
    }
    return null;
  }

  int get quizCorrect => quizAnswers.entries.where((e) => pack.quiz[e.key].answerIndex == e.value).length;

  double? get speakingAverage {
    if (speaking.isEmpty) return null;
    return speaking.values.map((s) => s.score).reduce((a, b) => a + b) / speaking.length;
  }

  StudyState copyWith({
    LearnerProfile? profile,
    int? contentStep,
    bool? onboarded,
    Map<String, DayRecord>? log,
    Map<String, ReviewCard>? cards,
    TodayProgress? today,
    List<String>? lastAdjustmentReasons,
  }) => StudyState(
    now: now,
    pack: pack,
    profile: profile ?? this.profile,
    contentStep: contentStep ?? this.contentStep,
    onboarded: onboarded ?? this.onboarded,
    log: log ?? this.log,
    cards: cards ?? this.cards,
    today: today ?? this.today,
    lastAdjustmentReasons: lastAdjustmentReasons ?? this.lastAdjustmentReasons,
  );

  SavedData toSaved() => SavedData(
    profile: profile,
    contentStep: contentStep,
    onboarded: onboarded,
    log: log,
    cards: cards,
    today: today,
    lastReasons: lastAdjustmentReasons,
  );
}

/// 진단을 건너뛸 때 쓰는 기본 프로필 (B1.1)
LearnerProfile defaultProfile() =>
    LearnerProfile(overall: Level.fromStep(6), skills: {for (final s in Skill.values) s: Level.fromStep(6)});

class StudyController extends Notifier<StudyState> {
  @override
  StudyState build() {
    final now = ref.read(clockProvider)();
    final saved = ref.read(storeProvider).load();
    final todayKey = dateKey(now);
    final today = saved?.today?.date == todayKey ? saved!.today! : TodayProgress(date: todayKey);
    final profile = saved?.profile ?? defaultProfile();
    return StudyState(
      now: now,
      pack: ref.read(packBuilderProvider)(now),
      profile: profile,
      contentStep: saved?.contentStep ?? profile.overall.step,
      onboarded: saved?.onboarded ?? false,
      log: saved?.log ?? const {},
      cards: saved?.cards ?? const {},
      today: today,
      lastAdjustmentReasons: saved?.lastReasons ?? const [],
    );
  }

  DateTime get _today => state.now;

  void _set(StudyState next) {
    state = next;
    ref.read(storeProvider).save(next.toSaved());
  }

  TodayProgress _progress({
    Set<String>? done,
    Map<String, bool>? expressionKnown,
    Map<String, SelfRating>? wordRatings,
    Map<String, String>? spoken,
    Map<int, int>? quizAnswers,
    int? levelDelta,
  }) {
    final t = state.today;
    return TodayProgress(
      date: t.date,
      done: done ?? t.done,
      expressionKnown: expressionKnown ?? t.expressionKnown,
      wordRatings: wordRatings ?? t.wordRatings,
      spoken: spoken ?? t.spoken,
      quizAnswers: quizAnswers ?? t.quizAnswers,
      levelDelta: levelDelta ?? t.levelDelta,
    );
  }

  void setExpressionKnown(String id, bool known) {
    _set(state.copyWith(today: _progress(expressionKnown: {...state.expressionKnown, id: known})));
  }

  void rateWord(String id, SelfRating rating) {
    final card = state.cards[id] ?? ReviewCard.fresh(id, _today);
    _set(
      state.copyWith(
        today: _progress(wordRatings: {...state.wordRatings, id: rating}),
        cards: {...state.cards, id: Srs.rate(card, rating, _today)},
      ),
    );
  }

  void recordSpeaking(Sentence s, String heard) {
    _set(state.copyWith(today: _progress(spoken: {...state.today.spoken, s.id: heard})));
  }

  void answerQuiz(int index, int choice) {
    if (state.quizAnswers.containsKey(index)) return;
    final item = state.pack.quiz[index];
    final card = state.cards[item.id] ?? ReviewCard.fresh(item.id, _today);
    _set(
      state.copyWith(
        today: _progress(quizAnswers: {...state.quizAnswers, index: choice}),
        cards: {
          ...state.cards,
          item.id: Srs.answer(card, correct: item.answerIndex == choice, today: _today),
        },
      ),
    );
  }

  void complete(RoutineStep step) {
    if (state.done.contains(step)) return;
    _set(state.copyWith(today: _progress(done: {...state.today.done, step.name})));
    if (state.allDone) _finishDay();
  }

  void applyLevelTest(LearnerProfile profile) {
    _set(state.copyWith(profile: profile, contentStep: profile.overall.step, onboarded: true));
  }

  void skipLevelTest() => applyLevelTest(defaultProfile());

  void _finishDay() {
    final s = state;
    final result = DailyResult(
      quizCorrect: s.quizCorrect,
      quizTotal: s.pack.quiz.length,
      wordsKnown: s.wordRatings.values.where((r) => r == SelfRating.know).length,
      wordsTotal: s.pack.words.length,
      speakingAverage: s.speakingAverage,
      expressionsAlreadyKnown: s.expressionKnown.values.where((k) => k).length,
      expressionsTotal: s.pack.expressions.length,
    );
    final adj = DailyAdjuster.adjust(
      profile: s.profile,
      currentContentStep: s.contentStep,
      today: result,
      yesterdayAccuracy: s.yesterdayAccuracy,
    );
    _set(
      s.copyWith(
        profile: adj.profile,
        contentStep: adj.nextContentStep,
        today: _progress(levelDelta: adj.levelDelta),
        log: {
          ...s.log,
          dateKey(_today): DayRecord(
            accuracy: result.accuracy,
            levelScore: adj.profile.overall.score,
            speakingAverage: result.speakingAverage,
          ),
        },
        lastAdjustmentReasons: adj.reasons,
      ),
    );
  }
}

final studyProvider = NotifierProvider<StudyController, StudyState>(StudyController.new);
