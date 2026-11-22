import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/tts.dart';
import '../data/models.dart';
import '../data/pack_source.dart';
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

/// 서버를 쓸 수 없을 때의 기본 팩
final fallbackPackProvider = Provider<DailyPack Function(DateTime)>((ref) => samplePack);

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
    this.settings = const AppSettings(),
    this.learned = const {},
    this.packs = const {},
    this.packLoading = false,
    this.packError,
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
  final AppSettings settings;
  final Map<String, LearnedItem> learned;
  final Map<String, Map<String, Object?>> packs;

  /// 오늘의 맞춤 팩을 만드는 중
  final bool packLoading;

  /// 맞춤 팩을 받지 못한 이유 (기본 팩으로 진행 중)
  final String? packError;

  /// 오늘 아직 아무것도 시작하지 않았는지 (팩을 바꿔도 되는지)
  bool get untouched =>
      today.done.isEmpty &&
      today.expressionKnown.isEmpty &&
      today.wordRatings.isEmpty &&
      today.spoken.isEmpty &&
      today.quizAnswers.isEmpty;

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
    DailyPack? pack,
    Map<String, LearnedItem>? learned,
    Map<String, Map<String, Object?>>? packs,
    bool? packLoading,
    String? Function()? packError,
    LearnerProfile? profile,
    int? contentStep,
    bool? onboarded,
    Map<String, DayRecord>? log,
    Map<String, ReviewCard>? cards,
    TodayProgress? today,
    List<String>? lastAdjustmentReasons,
    AppSettings? settings,
  }) => StudyState(
    now: now,
    pack: pack ?? this.pack,
    learned: learned ?? this.learned,
    packs: packs ?? this.packs,
    packLoading: packLoading ?? this.packLoading,
    packError: packError == null ? this.packError : packError(),
    profile: profile ?? this.profile,
    contentStep: contentStep ?? this.contentStep,
    onboarded: onboarded ?? this.onboarded,
    log: log ?? this.log,
    cards: cards ?? this.cards,
    today: today ?? this.today,
    lastAdjustmentReasons: lastAdjustmentReasons ?? this.lastAdjustmentReasons,
    settings: settings ?? this.settings,
  );

  SavedData toSaved() => SavedData(
    profile: profile,
    contentStep: contentStep,
    onboarded: onboarded,
    log: log,
    cards: cards,
    today: today,
    lastReasons: lastAdjustmentReasons,
    settings: settings,
    packs: packs,
    learned: learned,
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
    final onboarded = saved?.onboarded ?? false;
    final learned = saved?.learned ?? const <String, LearnedItem>{};
    // 지난 날짜의 팩은 버린다
    final packs = {
      for (final e in (saved?.packs ?? const <String, Map<String, Object?>>{}).entries)
        if (e.key.compareTo(todayKey) >= 0) e.key: e.value,
    };

    final source = ref.read(packSourceProvider);
    final cached = packs[todayKey];
    DailyPack pack;
    var loading = false;
    if (cached != null) {
      pack = packFromJson(cached, learned: learned, today: now);
    } else {
      pack = ref.read(fallbackPackProvider)(now);
      if (source != null && onboarded && today.done.isEmpty) {
        loading = true;
        Future.microtask(loadTodayPack);
      }
    }

    return StudyState(
      now: now,
      pack: pack,
      profile: profile,
      contentStep: saved?.contentStep ?? profile.overall.step,
      onboarded: onboarded,
      log: saved?.log ?? const {},
      cards: saved?.cards ?? const {},
      today: today,
      lastAdjustmentReasons: saved?.lastReasons ?? const [],
      settings: saved?.settings ?? const AppSettings(),
      learned: loading ? learned : registerLearned(learned, pack),
      packs: packs,
      packLoading: loading,
    );
  }

  /// 오늘의 맞춤 팩을 서버(Claude)에서 받아온다. 실패하면 기본 팩으로 계속한다.
  Future<void> loadTodayPack() async {
    final source = ref.read(packSourceProvider);
    if (source == null) return;
    final s0 = state;
    if (!s0.untouched || s0.pack.fromClaude) {
      if (s0.packLoading) state = s0.copyWith(packLoading: false);
      return;
    }
    state = s0.copyWith(packLoading: true, packError: () => null);
    try {
      final json = await source.fetch(
        buildPackRequest(
          date: s0.now,
          profile: s0.profile,
          contentStep: s0.contentStep,
          learned: s0.learned,
          cards: s0.cards,
        ),
      );
      final pack = packFromJson(json, learned: state.learned, today: state.now);
      if (!state.untouched) {
        // 기다리는 동안 기본 팩으로 이미 시작했다면 오늘 팩은 바꾸지 않는다.
        state = state.copyWith(packLoading: false);
        return;
      }
      _set(
        state.copyWith(
          pack: pack,
          learned: registerLearned(state.learned, pack),
          packs: {...state.packs, dateKey(state.now): json},
          packLoading: false,
        ),
      );
    } catch (e) {
      final message = e is PackFetchException ? e.message : '맞춤 학습을 만들지 못했어요.';
      _set(
        state.copyWith(
          packLoading: false,
          packError: () => message,
          learned: registerLearned(state.learned, state.pack),
        ),
      );
    }
  }

  /// 루틴을 끝낸 뒤 내일 팩을 미리 받아 둔다 (아침에 기다리지 않고 바로 시작할 수 있게).
  Future<void> _prefetchTomorrow() async {
    final source = ref.read(packSourceProvider);
    if (source == null) return;
    final s = state;
    final tomorrow = DateTime(s.now.year, s.now.month, s.now.day + 1);
    try {
      final json = await source.fetch(
        buildPackRequest(
          date: tomorrow,
          profile: s.profile,
          contentStep: s.contentStep,
          learned: s.learned,
          cards: s.cards,
        ),
      );
      _set(state.copyWith(packs: {...state.packs, dateKey(tomorrow): json}));
    } catch (_) {
      // 내일 아침 앱을 열 때 다시 시도한다.
    }
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
    final card = state.cards[id] ?? ReviewCard.fresh(id, _today);
    _set(
      state.copyWith(
        today: _progress(expressionKnown: {...state.expressionKnown, id: known}),
        cards: {...state.cards, id: Srs.rate(card, known ? SelfRating.know : SelfRating.dontKnow, _today)},
      ),
    );
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
    // 문제가 다루는 표현·단어의 복습 일정을 바꾼다
    final cardId = item.itemId ?? item.id;
    final card = state.cards[cardId] ?? ReviewCard.fresh(cardId, _today);
    _set(
      state.copyWith(
        today: _progress(quizAnswers: {...state.quizAnswers, index: choice}),
        cards: {
          ...state.cards,
          cardId: Srs.answer(card, correct: item.answerIndex == choice, today: _today),
        },
      ),
    );
  }

  void complete(RoutineStep step) {
    if (state.done.contains(step)) return;
    _set(state.copyWith(today: _progress(done: {...state.today.done, step.name})));
    if (state.allDone) {
      _finishDay();
      _prefetchTomorrow();
    }
  }

  void applyLevelTest(LearnerProfile profile) {
    _set(state.copyWith(profile: profile, contentStep: profile.overall.step, onboarded: true));
    // 진단 결과에 맞춰 오늘의 팩을 만든다
    if (state.untouched && !state.pack.fromClaude) loadTodayPack();
  }

  void skipLevelTest() => applyLevelTest(defaultProfile());

  void updateSettings(AppSettings settings) => _set(state.copyWith(settings: settings));

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

/// 설정(음성·속도)을 반영해 영어 문장을 읽어준다.
final sayProvider = Provider<Future<void> Function(String text, {bool slow})>((ref) {
  final speaker = ref.watch(speakerProvider);
  return (String text, {bool slow = false}) {
    final st = ref.read(studyProvider).settings;
    speaker.configure(voice: st.voice, speed: st.speed);
    return speaker.speak(text, slow: slow);
  };
});
