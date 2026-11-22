import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/tts.dart';
import '../core/notifications/reminder.dart';
import '../data/models.dart';
import '../data/pack_source.dart';
import '../data/sample_content.dart';
import '../data/store.dart';
import '../domain/daily_adjuster.dart';
import '../domain/level.dart';
import '../domain/pack_check.dart';
import '../domain/speech_score.dart';
import '../domain/srs.dart';
import '../domain/study_log.dart';

/// 소리 내지 않고 속으로 따라 한 문장 표시 (점수 평균에서 뺀다)
const kSilentAttempt = '<silent>';

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
      if (today.spoken.containsKey(s.id) && today.spoken[s.id] != kSilentAttempt)
        s.id: scoreSpeech(s.en, today.spoken[s.id]!),
  };

  /// 말했거나 속으로 따라 한 문장 수 (진행률용)
  int get spokenCount => today.spoken.length;

  bool hasSpoken(String sentenceId) => today.spoken.containsKey(sentenceId);

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

/// 진단을 건너뛸 때 쓰는 기본 프로필 (기본 B1.1, 초급이면 A2.2)
LearnerProfile defaultProfile({int step = 6}) =>
    LearnerProfile(overall: Level.fromStep(step), skills: {for (final s in Skill.values) s: Level.fromStep(step)});

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
    final cachedPack = packs[todayKey] == null ? null : _parsePack(packs[todayKey]!, learned, now);
    if (packs[todayKey] != null && cachedPack == null) packs.remove(todayKey); // 깨진 캐시는 버린다
    DailyPack pack;
    var loading = false;
    if (cachedPack != null) {
      pack = cachedPack;
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

  /// 서버 JSON 을 팩으로 읽고 검사한다. 읽을 수 없거나 문제가 있으면 null.
  static DailyPack? _parsePack(Map<String, Object?> json, Map<String, LearnedItem> learned, DateTime now) {
    try {
      final pack = packFromJson(json, learned: learned, today: now);
      return checkPack(pack).isEmpty ? pack : null;
    } catch (_) {
      return null;
    }
  }

  /// 요청이 겹치면 가장 최근 요청의 결과만 반영한다.
  int _packRequest = 0;

  /// 오늘의 맞춤 팩을 서버(Claude)에서 받아온다. 실패하면 기본 팩으로 계속한다.
  /// [force] 이면 이미 받은 팩이 있어도 다시 받는다 (레벨 재진단 후).
  Future<void> loadTodayPack({bool force = false}) async {
    final source = ref.read(packSourceProvider);
    if (source == null) return;
    final s0 = state;
    if (!s0.untouched || (s0.pack.fromClaude && !force)) {
      if (s0.packLoading) state = s0.copyWith(packLoading: false);
      return;
    }
    final request = ++_packRequest;
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
      if (request != _packRequest || !ref.mounted) return; // 더 새 요청이 있다
      final pack = _parsePack(json, state.learned, state.now);
      if (pack == null) throw const PackFetchException('받은 학습 내용에 문제가 있어요.');
      if (!state.untouched) {
        // 기다리는 동안 기본 팩으로 이미 시작했다면 오늘 팩은 바꾸지 않는다 (시작한 팩은 배운 항목으로 등록).
        _set(state.copyWith(packLoading: false, learned: registerLearned(state.learned, state.pack)));
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
      if (request != _packRequest || !ref.mounted) return;
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
      if (!ref.mounted || _parsePack(json, state.learned, tomorrow) == null) return;
      _set(state.copyWith(packs: {...state.packs, dateKey(tomorrow): json}));
    } catch (_) {
      // 내일 아침 앱을 열 때 다시 시도한다.
    }
  }

  DateTime get _today => state.now;

  /// 기다리지 않고 기본 팩으로 오늘 학습을 시작한다.
  void startWithFallback() {
    _packRequest++; // 진행 중인 요청 결과는 오늘 팩으로 쓰지 않는다
    _set(state.copyWith(packLoading: false, learned: registerLearned(state.learned, state.pack)));
  }

  /// 날짜가 바뀌었으면(자정을 넘겼거나 다음 날 앱으로 돌아옴) 오늘 기준으로 다시 만든다.
  void refreshIfNewDay() {
    if (dateKey(ref.read(clockProvider)()) != state.today.date) ref.invalidateSelf();
  }

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

  /// 복습 세션에서 카드를 평가한다 (오늘 루틴 진행과는 별개)
  void reviewCard(String id, SelfRating rating) {
    final card = state.cards[id] ?? ReviewCard.fresh(id, _today);
    _set(state.copyWith(cards: {...state.cards, id: Srs.rate(card, rating, _today)}));
  }

  /// 오늘 복습할 표현·단어 (자주 틀린 것, 오래 밀린 것부터)
  List<LearnedItem> dueReviews({int limit = 20}) => [
    for (final c in Srs.dueToday(
      state.cards.values.where((c) => state.learned.containsKey(c.itemId)),
      _today,
      limit: limit,
    ))
      state.learned[c.itemId]!,
  ];

  /// 단어 평가를 실수로 눌렀을 때 되돌린다 ([previous] 는 평가 전 카드, 없었으면 null)
  void undoWordRating(String id, ReviewCard? previous) {
    final ratings = {...state.wordRatings}..remove(id);
    final cards = {...state.cards};
    previous == null ? cards.remove(id) : cards[id] = previous;
    _set(
      state.copyWith(
        today: _progress(wordRatings: ratings),
        cards: cards,
      ),
    );
  }

  /// 소리 내기 어려운 곳에서: 듣고 속으로 따라 한 것으로 기록 (점수 없음)
  void recordSilent(Sentence s) => recordSpeaking(s, kSilentAttempt);

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
      syncReminder();
    }
  }

  void applyLevelTest(LearnerProfile profile) {
    final todayKey = dateKey(state.now);
    // 이전 레벨로 미리 받아 둔 팩은 버린다 (오늘 팩은 아직 시작 전일 때만)
    final packs = {
      for (final e in state.packs.entries)
        if (e.key == todayKey && !state.untouched) e.key: e.value,
    };
    _set(state.copyWith(profile: profile, contentStep: profile.overall.step, onboarded: true, packs: packs));
    // 진단 결과에 맞춰 오늘의 팩을 만든다
    if (state.untouched) loadTodayPack(force: true);
  }

  /// 진단을 건너뛸 때: "짧은 대화가 가능한지" 한 가지만 물어 A2 / B1 로 시작한다.
  void skipLevelTest({bool beginner = false}) => applyLevelTest(beginner ? defaultProfile(step: 4) : defaultProfile());

  void updateSettings(AppSettings settings) => _set(state.copyWith(settings: settings));

  /// 아침 알림을 켜거나(분) 끈다(null). 권한이 없어 예약하지 못하면 false.
  Future<bool> setReminder(int? minutes) async {
    final reminder = ref.read(reminderProvider);
    if (minutes == null) {
      await reminder.cancel();
      _set(state.copyWith(settings: state.settings.copyWith(reminderMinutes: () => null)));
      return true;
    }
    final (title, body) = reminderText(state.streakDays);
    final ok = await reminder.scheduleDaily(minutes, title: title, body: body);
    if (ok) {
      reminderBlocked.value = false;
      _set(state.copyWith(settings: state.settings.copyWith(reminderMinutes: () => minutes)));
    }
    return ok;
  }

  /// 앱을 열 때·루틴을 끝냈을 때 알림 문구(연속 학습일)를 새로 고친다. 권한은 묻지 않는다.
  /// 휴대폰 설정에서 알림을 꺼 두었으면 [reminderBlocked] 로 알린다.
  Future<void> syncReminder() async {
    final minutes = state.settings.reminderMinutes;
    if (minutes == null) return;
    final (title, body) = reminderText(state.streakDays);
    final ok = await ref.read(reminderProvider).scheduleDaily(minutes, title: title, body: body, askPermission: false);
    if (ref.mounted) reminderBlocked.value = !ok;
  }

  /// 알림이 켜져 있지만 휴대폰에서 권한을 꺼 둔 상태
  final reminderBlocked = ValueNotifier(false);

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
