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

  /// 연속 학습 (쉬는 날 포함 계산)
  late final StreakInfo streak = computeStreakInfo(log.keys, now);
  int get streakDays => streak.days;

  /// 최고 연속 기록 (쉬는 날로 이어진 지금 기록이 더 길면 그것)
  int get longestStreak {
    final raw = computeLongestStreak(log.keys);
    return raw > streakDays ? raw : streakDays;
  }

  /// 오늘을 빼고 계산한 최고 기록 (오늘 완료로 기록을 새로 세웠는지 보려고)
  int get previousLongest => computeLongestStreak(log.keys.where((k) => k != dateKey(now)));

  /// 이번 달에 루틴을 끝낸 날짜(일)
  Set<int> get studiedDays => {
    for (final k in log.keys)
      if (parseDateKey(k).year == now.year && parseDateKey(k).month == now.month) parseDateKey(k).day,
  };

  /// 이번 달 중 쉬는 날로 메운 날
  Set<int> get restDaysThisMonth => {
    for (final k in streak.restDays)
      if (parseDateKey(k).year == now.year && parseDateKey(k).month == now.month) parseDateKey(k).day,
  };

  /// 어제 난이도 판단에 쓴 정답률 (오늘과 같은 지표로 비교: 배운 것 정답률이 있으면 그것)
  double? get yesterdayAccuracy {
    final r = previousRecord(log, now);
    return r == null ? null : r.newAccuracy ?? r.accuracy;
  }

  bool get allDone => done.length == RoutineStep.values.length;

  /// 지금 이어서 할 단계
  RoutineStep? get current {
    for (final s in RoutineStep.values) {
      if (!done.contains(s)) return s;
    }
    return null;
  }

  /// 복습 세션에 한 번에 나오는 최대 카드 수
  static const reviewSessionSize = 20;

  /// 지금 복습 세션을 열면 나올 카드 수 (오늘 퀴즈에 나올 항목은 퀴즈 전까지 제외, 최대 20장)
  int get dueCount {
    final inQuiz = done.contains(RoutineStep.quiz) ? const <String>{} : {for (final q in pack.quiz) ?q.itemId};
    final n = cards.values
        .where((c) => learned.containsKey(c.itemId) && !inQuiz.contains(c.itemId) && c.isDue(now))
        .length;
    return n > reviewSessionSize ? reviewSessionSize : n;
  }

  /// 복습 세션 예상 시간(분): 카드 10장에 약 1분
  int get reviewMinutes => (dueCount / 10).ceil().clamp(1, 3);

  int get quizCorrect =>
      quizAnswers.entries.where((e) => e.key < pack.quiz.length && pack.quiz[e.key].answerIndex == e.value).length;

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

/// 하루가 바뀌는 시각. 자정 직후 공부하던 것이 다음 날로 넘어가지 않도록 새벽 4시를 경계로 쓴다.
const dayStartHour = 4;

/// [now] 가 속한 '학습일' (새벽 4시 전이면 전날)
DateTime studyDay(DateTime now) {
  final shifted = now.subtract(const Duration(hours: dayStartHour));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// 팩을 구분하는 값. 오늘 진행이 어느 팩에 대한 것인지 확인하는 데 쓴다.
String packIdOf(DailyPack p) => '${dateKey(p.date)}|${p.topic}|${p.fromClaude ? 'c' : 's'}|${p.quiz.length}';

/// 알림이 켜져 있지만 휴대폰에서 권한을 꺼 둔 상태
class ReminderBlocked extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// '소리 내기 어려워요' 모드. 지하철 등에서 켜 두면 앱을 쓰는 동안 말하기 화면에 계속 유지된다.
class QuietMode extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final quietModeProvider = NotifierProvider<QuietMode, bool>(QuietMode.new);

final reminderBlockedProvider = NotifierProvider<ReminderBlocked, bool>(ReminderBlocked.new);

class StudyController extends Notifier<StudyState> {
  @override
  StudyState build() {
    // 다시 만들어질 때(날짜 변경 등) 진행 중이던 요청 결과는 버린다
    ref.onDispose(() {
      _packRequest++;
      _prefetchRequest++;
    });
    final now = studyDay(ref.read(clockProvider)());
    final saved = ref.read(storeProvider).load();
    final todayKey = dateKey(now);
    var today = saved?.today?.date == todayKey ? saved!.today! : TodayProgress(date: todayKey);
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
    }

    // 오늘 진행이 다른 팩에 대한 것이면(캐시가 버려졌거나 바뀜) 번호 기준 진행이 어긋나므로 비운다
    final id = packIdOf(pack);
    var cards = saved?.cards ?? const <String, ReviewCard>{};
    if (today.packId != null && today.packId != id) {
      // 지운 진행으로 바뀐 복습 카드는 원래대로 돌린다 (다시 평가할 때 두 번 오르지 않게)
      cards = {...cards};
      for (final e in today.cardsBefore.entries) {
        e.value == null ? cards.remove(e.key) : cards[e.key] = e.value!;
      }
      today = TodayProgress(date: todayKey, packId: id, regenCount: today.regenCount);
    } else if (today.packId == null) {
      today = _withPackId(today, id);
    }

    if (cachedPack == null && source != null && onboarded && _isUntouched(today)) {
      loading = true;
      Future.microtask(loadTodayPack);
    }

    return StudyState(
      now: now,
      pack: pack,
      profile: profile,
      contentStep: saved?.contentStep ?? profile.overall.step,
      onboarded: onboarded,
      log: saved?.log ?? const {},
      cards: cards,
      today: today,
      lastAdjustmentReasons: saved?.lastReasons ?? const [],
      settings: saved?.settings ?? const AppSettings(),
      learned: loading ? learned : registerLearned(learned, pack),
      packs: packs,
      packLoading: loading,
    );
  }

  static bool _isUntouched(TodayProgress t) =>
      t.done.isEmpty && t.expressionKnown.isEmpty && t.wordRatings.isEmpty && t.spoken.isEmpty && t.quizAnswers.isEmpty;

  static TodayProgress _withPackId(TodayProgress t, String id) => TodayProgress(
    date: t.date,
    done: t.done,
    expressionKnown: t.expressionKnown,
    wordRatings: t.wordRatings,
    spoken: t.spoken,
    quizAnswers: t.quizAnswers,
    levelDelta: t.levelDelta,
    packId: id,
    cardsBefore: t.cardsBefore,
    regenCount: t.regenCount,
  );

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
  int _prefetchRequest = 0;

  /// 하루에 오늘 팩을 Claude 로 만들 수 있는 횟수 (첫 요청 + 재시도·재진단, 비용 방지)
  static const maxFetchPerDay = 4;

  /// 오늘의 맞춤 팩을 서버(Claude)에서 받아온다. 실패하면 기본 팩으로 계속한다.
  /// [force] 이면 이미 받은 팩이 있어도 다시 받는다 (레벨 재진단 후).
  Future<void> loadTodayPack({bool force = false}) async {
    if (!ref.mounted) return;
    final source = ref.read(packSourceProvider);
    if (source == null) return;
    final s0 = state;
    if (!s0.untouched || (s0.pack.fromClaude && !force)) {
      if (s0.packLoading) state = s0.copyWith(packLoading: false);
      return;
    }
    if (s0.today.regenCount >= maxFetchPerDay) {
      _set(s0.copyWith(packLoading: false, packError: () => '오늘은 맞춤 학습을 충분히 만들었어요. 기본 학습으로 진행해요.'));
      return;
    }
    final request = ++_packRequest;
    // 요청 횟수를 먼저 저장한다 (기다리다 앱을 꺼도 세어지게)
    _set(
      s0.copyWith(
        packLoading: true,
        packError: () => null,
        today: _progress(regenCount: s0.today.regenCount + 1),
      ),
    );
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
      if (!ref.mounted || request != _packRequest) return; // 더 새 요청이 있다
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
          today: _withPackId(state.today, packIdOf(pack)),
          learned: registerLearned(state.learned, pack),
          packs: {...state.packs, dateKey(state.now): json},
          packLoading: false,
        ),
      );
    } catch (e) {
      if (!ref.mounted || request != _packRequest) return;
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
    final request = ++_prefetchRequest;
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
      // 재진단 등으로 더 새 요청이 있었으면 옛 레벨 팩은 저장하지 않는다
      if (!ref.mounted || request != _prefetchRequest || _parsePack(json, state.learned, tomorrow) == null) return;
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

  /// 학습일이 바뀌었으면(새벽 4시를 넘김) 오늘 기준으로 다시 만든다.
  /// 루틴을 하는 중이면 진행을 지우지 않도록 미루고, 홈으로 돌아왔을 때([fromHome]) 새로 고친다.
  /// 새로 고쳤으면 true (호출한 쪽에서 새 상태로 알림 문구를 갱신한다).
  bool refreshIfNewDay({bool fromHome = false}) {
    if (dateKey(studyDay(ref.read(clockProvider)())) == state.today.date) return false;
    // 완료 화면을 보는 중에 결과가 사라지지 않도록, 끝낸 날도 홈에 있을 때만 바꾼다
    if (state.untouched || fromHome) {
      ref.invalidateSelf();
      return true;
    }
    return false;
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
    Map<String, ReviewCard?>? cardsBefore,
    int? regenCount,
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
      packId: t.packId,
      cardsBefore: cardsBefore ?? t.cardsBefore,
      regenCount: regenCount ?? t.regenCount,
    );
  }

  /// 오늘 루틴에서의 자가 평가. 평가를 바꾸면 '오늘 처음 평가하기 전 카드'에서 다시 계산해
  /// 여러 번 눌러도 단계가 계속 오르지 않게 한다.
  ({Map<String, ReviewCard> cards, Map<String, ReviewCard?> before}) _rateFromBaseline(String id, SelfRating rating) {
    final before = {...state.today.cardsBefore};
    if (!before.containsKey(id)) before[id] = state.cards[id];
    final base = before[id] ?? ReviewCard.fresh(id, _today);
    return (cards: {...state.cards, id: Srs.rate(base, rating, _today)}, before: before);
  }

  void setExpressionKnown(String id, bool known) {
    // 같은 선택을 다시 누름, 또는 끝낸 단계를 다시 보는 중 (퀴즈로 바뀐 복습 일정을 덮어쓰지 않게)
    if (state.expressionKnown[id] == known || state.done.contains(RoutineStep.expressions)) return;
    final r = _rateFromBaseline(id, known ? SelfRating.know : SelfRating.dontKnow);
    _set(
      state.copyWith(
        today: _progress(expressionKnown: {...state.expressionKnown, id: known}, cardsBefore: r.before),
        cards: r.cards,
      ),
    );
  }

  void rateWord(String id, SelfRating rating) {
    if (state.wordRatings[id] == rating || state.done.contains(RoutineStep.words)) return;
    final r = _rateFromBaseline(id, rating);
    _set(
      state.copyWith(
        today: _progress(wordRatings: {...state.wordRatings, id: rating}, cardsBefore: r.before),
        cards: r.cards,
      ),
    );
  }

  /// 복습 세션에서 카드를 평가한다 (오늘 루틴 진행과는 별개)
  void reviewCard(String id, SelfRating rating) {
    final card = state.cards[id] ?? ReviewCard.fresh(id, _today);
    _set(state.copyWith(cards: {...state.cards, id: Srs.rate(card, rating, _today)}));
  }

  /// 오늘 복습할 표현·단어 (자주 틀린 것, 오래 밀린 것부터)
  /// 오늘 퀴즈에 나올 항목은 퀴즈를 마칠 때까지 빼 둔다 (퀴즈로 확인해야 졸업할 수 있게).
  List<LearnedItem> dueReviews({int limit = 20}) {
    final inQuiz = state.done.contains(RoutineStep.quiz)
        ? const <String>{}
        : {for (final q in state.pack.quiz) ?q.itemId};
    return _dueReviews(limit, inQuiz);
  }

  List<LearnedItem> _dueReviews(int limit, Set<String> exclude) => [
    for (final c in Srs.dueToday(
      state.cards.values.where((c) => state.learned.containsKey(c.itemId) && !exclude.contains(c.itemId)),
      _today,
      limit: limit,
    ))
      state.learned[c.itemId]!,
  ];

  /// 단어 평가를 실수로 눌렀을 때 되돌린다. 단어 단계를 이미 끝냈으면 무시한다.
  void undoWordRating(String id) {
    if (state.done.contains(RoutineStep.words) || !state.wordRatings.containsKey(id)) return;
    final ratings = {...state.wordRatings}..remove(id);
    final before = {...state.today.cardsBefore};
    final cards = {...state.cards};
    if (before.containsKey(id)) {
      final previous = before.remove(id);
      previous == null ? cards.remove(id) : cards[id] = previous;
    }
    _set(
      state.copyWith(
        today: _progress(wordRatings: ratings, cardsBefore: before),
        cards: cards,
      ),
    );
  }

  /// 소리 내기 어려운 곳에서: 듣고 속으로 따라 한 것으로 기록 (점수 없음)
  /// 이미 소리 내어 받은 점수가 있으면 지우지 않는다.
  void recordSilent(Sentence s) {
    if (!state.today.spoken.containsKey(s.id)) recordSpeaking(s, kSilentAttempt);
  }

  void recordSpeaking(Sentence s, String heard) {
    _set(state.copyWith(today: _progress(spoken: {...state.today.spoken, s.id: heard})));
  }

  void answerQuiz(int index, int choice) {
    if (state.quizAnswers.containsKey(index) || index >= state.pack.quiz.length) return;
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
    final untouched = state.untouched;
    final canRegen = state.today.regenCount < maxFetchPerDay;
    _prefetchRequest++; // 옛 레벨로 받던 내일 팩은 저장하지 않는다
    _packRequest++; // 옛 레벨로 받던 오늘 팩도 쓰지 않는다
    // 이전 레벨로 미리 받아 둔 팩은 버린다. 오늘 팩은 아직 시작 전이고 다시 만들 수 있을 때만 버린다.
    final dropToday = untouched && canRegen && ref.read(packSourceProvider) != null;
    final packs = {
      for (final e in state.packs.entries)
        if (e.key == todayKey && !dropToday) e.key: e.value,
    };
    final fallback = dropToday ? ref.read(fallbackPackProvider)(state.now) : null;
    _set(
      state.copyWith(
        profile: profile,
        contentStep: profile.overall.step,
        onboarded: true,
        packs: packs,
        // 지운 팩으로 공부하지 않도록, 새 팩이 오기 전까지는 기본 팩을 보여준다
        pack: fallback,
        today: fallback == null
            ? null
            : TodayProgress(date: todayKey, packId: packIdOf(fallback), regenCount: state.today.regenCount),
        packLoading: false,
      ),
    );
    // 진단 결과에 맞춰 오늘의 팩을 만든다
    if (dropToday) loadTodayPack(force: true);
  }

  /// 진단을 건너뛸 때: "짧은 대화가 가능한지" 한 가지만 물어 A2 / B1 로 시작한다.
  void skipLevelTest({bool beginner = false}) => applyLevelTest(beginner ? defaultProfile(step: 4) : defaultProfile());

  void updateSettings(AppSettings settings) => _set(state.copyWith(settings: settings));

  /// 첫 완료 화면에서 알림을 제안했음을 기록한다 (다시 묻지 않게)
  void markReminderOffered() {
    if (!state.settings.reminderOffered) {
      _set(state.copyWith(settings: state.settings.copyWith(reminderOffered: true)));
    }
  }

  /// 아침 알림을 켜거나(분) 끈다(null). 권한이 없어 예약하지 못하면 false.
  Future<bool> setReminder(int? minutes) async {
    final reminder = ref.read(reminderProvider);
    if (minutes == null) {
      await reminder.cancel();
      _set(state.copyWith(settings: state.settings.copyWith(reminderMinutes: () => null)));
      return true;
    }
    final (title, body) = reminderText(state.streakDays, longest: state.longestStreak);
    final ok = await reminder.scheduleDaily(minutes, title: title, body: body, notBefore: _nextReminderStart());
    if (!ref.mounted) return ok;
    if (ok) {
      ref.read(reminderBlockedProvider.notifier).set(false);
      _set(state.copyWith(settings: state.settings.copyWith(reminderMinutes: () => minutes)));
    }
    return ok;
  }

  /// 앱을 열 때·루틴을 끝냈을 때 알림 문구(연속 학습일)를 새로 고친다. 권한은 묻지 않는다.
  /// 휴대폰 설정에서 알림을 꺼 두었으면 [reminderBlockedProvider] 로 알린다.
  Future<void> syncReminder() async {
    final minutes = state.settings.reminderMinutes;
    if (minutes == null) return;
    final (title, body) = reminderText(state.streakDays, longest: state.longestStreak);
    final ok = await ref
        .read(reminderProvider)
        .scheduleDaily(minutes, title: title, body: body, askPermission: false, notBefore: _nextReminderStart());
    if (ref.mounted) ref.read(reminderBlockedProvider.notifier).set(!ok);
  }

  /// 오늘 루틴을 이미 끝냈으면 오늘 남은 알림은 건너뛰고 다음 학습일(새벽 4시 이후)부터 알린다.
  DateTime? _nextReminderStart() {
    if (!state.allDone) return null;
    final d = state.now;
    return DateTime(d.year, d.month, d.day + 1, dayStartHour);
  }

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
      reviewTotal: s.pack.quiz.where((q) => q.isReview).length,
      reviewCorrect: [
        for (final e in s.quizAnswers.entries)
          if (e.key < s.pack.quiz.length && s.pack.quiz[e.key].isReview && s.pack.quiz[e.key].answerIndex == e.value) e,
      ].length,
    );
    final adj = DailyAdjuster.adjust(
      profile: s.profile,
      currentContentStep: s.contentStep,
      today: result,
      yesterdayAccuracy: s.yesterdayAccuracy,
      date: s.now,
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
            newAccuracy: result.newAccuracy,
          ),
        },
        lastAdjustmentReasons: adj.reasons,
      ),
    );
  }
}

/// 학습일이 바뀌었으면 새로 고치고, 새 상태(연속 학습일)로 알림 문구를 갱신한다.
void refreshStudyDay(WidgetRef ref, {bool fromHome = false}) {
  if (!ref.read(studyProvider.notifier).refreshIfNewDay(fromHome: fromHome)) return;
  ref.read(studyProvider); // 새 상태로 다시 만든다
  ref.read(studyProvider.notifier).syncReminder();
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
