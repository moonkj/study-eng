import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/tts.dart';
import '../core/notifications/reminder.dart';
import '../data/models.dart';
import '../data/pack_source.dart';
import '../data/sample_content.dart';
import '../data/store.dart';
import '../data/toeic.dart';
import '../data/topic_map.dart';
import '../domain/daily_adjuster.dart';
import '../domain/level.dart';
import '../domain/pack_check.dart';
import '../domain/pack_prep.dart';
import '../domain/speech_score.dart';
import '../domain/srs.dart';
import '../domain/study_log.dart';
import '../domain/toeic_feedback.dart';
import '../domain/toeic_weakness.dart' show addDailyScore;

/// 소리 내지 않고 속으로 따라 한 문장 표시 (점수 평균에서 뺀다)
const kSilentAttempt = '<silent>';

/// 오늘의 루틴 4단계
enum RoutineStep { expressions, words, speaking, quiz }

/// 테스트에서 날짜를 고정할 수 있도록 시계를 주입한다.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 서버를 쓸 수 없을 때의 기본 팩 (콘텐츠 난이도 단계에 맞는 것: A2 이하 / B1 이상)
final fallbackPackProvider = Provider<DailyPack Function(DateTime date, int contentStep)>((ref) => samplePackFor);

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
    this.series,
    this.mocks = const [],
    this.toeicLog = const {},
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

  /// 주간 시리즈 대화 진행 상태
  final SeriesState? series;

  /// 토스 모의고사 결과 (오래된 것부터)
  final List<MockResult> mocks;

  /// 토스 루틴 점수 (날짜 → 유형 → 점수)
  final Map<String, Map<String, int>> toeicLog;

  /// 지금 토익스피킹 목표
  ToeicTarget get toeicTarget => settings.target;

  /// 가장 최근 모의고사(지금 목표로 본 것)가 목표에 닿았고, 아직 다음 목표 제안을 닫지 않았는지
  bool get targetReached {
    if (mocks.isEmpty || toeicTarget.next == null) return false;
    final m = mocks.last;
    // 지금 목표로 본 모의고사만 (목표를 올린 뒤에는 새 목표로 다시 봐야 한다)
    return m.target == toeicTarget.label &&
        meetsTarget(m.level, toeicTarget) &&
        settings.toeicSuggestDismissed != mockKey(m);
  }

  /// 오늘 루틴의 토스 문항 평균 점수 (한 것이 없으면 null)
  double? get toeicAverage {
    if (today.toeic.isEmpty) return null;
    return today.toeic.values.map((r) => r.score).reduce((a, b) => a + b) / today.toeic.length;
  }

  /// 오늘 아직 아무것도 시작하지 않았는지 (팩을 바꿔도 되는지)
  bool get untouched =>
      today.done.isEmpty &&
      today.expressionKnown.isEmpty &&
      today.wordRatings.isEmpty &&
      today.spoken.isEmpty &&
      today.toeic.isEmpty &&
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

  /// 최고 연속 기록 (쉬는 날로 이어진 기록 포함)
  int get longestStreak => streak.best;

  /// 오늘 완료를 빼고 계산한 연속 상태 (오늘 기록을 새로 세웠는지, 쉬는 날이 새로 생겼는지 보려고)
  late final StreakInfo previousStreak = computeStreakInfo(log.keys.where((k) => k != dateKey(now)), now);
  int get previousLongest => previousStreak.best;

  /// 어제부터 거슬러 올라가며 연달아 쓴 쉬는 날 수
  int get restsUsedRecently {
    var n = 0;
    var d = DateTime(now.year, now.month, now.day - 1);
    while (streak.restDays.contains(dateKey(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

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
    SeriesState? series,
    List<MockResult>? mocks,
    Map<String, Map<String, int>>? toeicLog,
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
    series: series ?? this.series,
    mocks: mocks ?? this.mocks,
    toeicLog: toeicLog ?? this.toeicLog,
  );

  /// 서버 팩이 아닌 기본 팩이고, 그 내용을 오늘 이전에 이미 배웠는지 (오프라인으로 같은 팩을 다시 하는 날)
  bool get isRepeatPack {
    if (pack.fromClaude) return false;
    final key = today.carriedFrom ?? dateKey(now);
    return pack.expressions.any((e) {
      final item = learned[e.id];
      return item != null && item.firstSeen != key;
    });
  }

  /// 저장할 때 더 이상 쓰지 않는 데이터를 정리한다 (저장 공간이 끝없이 늘지 않게)
  /// - 완전히 익힌 단어 카드
  /// - 180일 넘게 지났고 복습할 카드도 없는 배운 항목 (중복 회피는 최근 90일만 쓴다)
  SavedData toSaved() {
    final keptCards = {
      for (final e in cards.entries)
        // 완전히 익힌 카드는 버리되, 표현은 '내 표현'에 완전히 익힘으로 남도록 둔다 (하루 3개라 작다)
        if (!e.value.retired || learned[e.key]?.kind == 'expression') e.key: e.value,
    };
    final keptLearned = {
      for (final e in learned.entries)
        if (keptCards.containsKey(e.key) || daysBetween(parseDateKey(e.value.firstSeen), now) <= 180) e.key: e.value,
    };
    return _toSaved(keptCards, keptLearned);
  }

  SavedData _toSaved(Map<String, ReviewCard> cards, Map<String, LearnedItem> learned) => SavedData(
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
    series: series,
    mocks: mocks,
    toeicLog: toeicLog,
  );
}

/// 진단을 건너뛸 때 쓰는 기본 프로필 (기본 B1.1, 초급이면 A2.2)
LearnerProfile defaultProfile({int step = 6}) =>
    LearnerProfile(overall: Level.fromStep(step), skills: {for (final s in Skill.values) s: Level.fromStep(step)});

/// 하루가 바뀌는 시각. 자정 직후 공부하던 것이 다음 날로 넘어가지 않도록 새벽 4시를 경계로 쓴다.
const dayStartHour = 4;

/// [now] 가 속한 '학습일' (새벽 4시 전이면 전날)
DateTime studyDay(DateTime now) =>
    // 시각으로 판단한다 (4시간을 빼는 방식은 서머타임 전환일에 하루가 어긋난다)
    now.hour < dayStartHour ? DateTime(now.year, now.month, now.day - 1) : DateTime(now.year, now.month, now.day);

/// 팩을 구분하는 값. 오늘 진행이 어느 팩에 대한 것인지 확인하는 데 쓴다.
String packIdOf(DailyPack p) => '${dateKey(p.date)}|${p.topic}|${p.fromClaude ? 'c' : 's'}|${p.quiz.length}';

/// 알림이 켜져 있지만 휴대폰에서 권한을 꺼 둔 상태
class ReminderBlocked extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// '소리 내기 어려워요' 모드. 지하철 등에서 켜 두면 앱을 쓰는 동안 말하기 화면에 계속 유지된다.
/// 켜 둔 상태는 설정에 저장해 앱을 다시 켜도 유지한다.
class QuietMode extends Notifier<bool> {
  @override
  bool build() => ref.read(studyProvider).settings.quiet;

  void set(bool value) {
    state = value;
    final c = ref.read(studyProvider.notifier);
    c.updateSettings(ref.read(studyProvider).settings.copyWith(quiet: value));
  }
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
    final savedPacks = saved?.packs ?? const <String, Map<String, Object?>>{};
    final source = ref.read(packSourceProvider);
    var log = saved?.log ?? const <String, DayRecord>{};
    final contentStep = saved?.contentStep ?? profile.overall.step;

    // 지난 학습일 루틴을 끝내지 못하고 날이 바뀌었으면:
    // - 표현까지 했으면 그날을 3분 루틴 날로 기록한다 (연속 기록이 이어지게, 레벨·정답률 판단에는 쓰지 않는다)
    // - 남은 단계는 오늘 이어서 한다 (그날의 팩과 진행을 그대로 가져온다, 한 번만)
    final prev = saved?.today;
    if (onboarded &&
        prev != null &&
        prev.date.compareTo(todayKey) < 0 &&
        prev.carriedFrom == null &&
        !_isUntouched(prev) &&
        !(log[prev.date] != null && !log[prev.date]!.mini)) {
      final prevDate = parseDateKey(prev.date);
      final json = savedPacks[prev.date];
      final raw = json != null
          ? _parsePack(json, learned, prevDate)
          : ref.read(fallbackPackProvider)(prevDate, contentStep);
      final carried = raw == null ? null : _prepare(raw, log, prevDate);
      if (log[prev.date] == null && prev.done.contains(RoutineStep.expressions.name)) {
        log = {
          ...log,
          prev.date: DayRecord(accuracy: 0, levelScore: profile.overall.score, mini: true, topic: carried?.topic),
        };
      }
      if (carried != null && packIdOf(carried) == prev.packId) {
        today = _carry(prev, todayKey);
      }
    }
    final carriedFrom = today.carriedFrom;
    final packKey = carriedFrom ?? todayKey;
    final packDate = carriedFrom == null ? now : parseDateKey(carriedFrom);

    // 지난 날짜의 팩은 버린다 (이어서 하는 날의 팩은 둔다)
    final packs = {
      for (final e in savedPacks.entries)
        if (e.key.compareTo(todayKey) >= 0 || e.key == carriedFrom) e.key: e.value,
    };
    final cachedPack = packs[packKey] == null ? null : _parsePack(packs[packKey]!, learned, now);
    if (packs[packKey] != null && cachedPack == null) packs.remove(packKey); // 깨진 캐시는 버린다
    var loading = false;
    final pack = _prepare(cachedPack ?? ref.read(fallbackPackProvider)(packDate, contentStep), log, packDate);

    // 오늘 진행이 다른 팩에 대한 것이면(캐시가 버려졌거나 바뀜) 번호 기준 진행이 어긋나므로 비운다
    final id = packIdOf(pack);
    var cards = saved?.cards ?? const <String, ReviewCard>{};
    // (오늘 루틴을 이미 끝냈으면 기록·레벨이 반영됐으므로 진행을 지우지 않는다: 다시 하면 두 번 반영되므로)
    final finishedToday = saved?.log[todayKey] != null && !saved!.log[todayKey]!.mini;
    if (today.packId != null && today.packId != id && finishedToday) {
      today = _withPackId(today, id);
    } else if (today.packId != null && today.packId != id) {
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
      contentStep: contentStep,
      onboarded: onboarded,
      log: log,
      cards: cards,
      today: today,
      lastAdjustmentReasons: saved?.lastReasons ?? const [],
      settings: saved?.settings ?? const AppSettings(),
      // 진단 전에는 등록하지 않는다 (보지도 않은 기본 팩이 '배운 항목'으로 남지 않게)
      learned: loading || !onboarded ? learned : registerLearned(learned, pack),
      packs: packs,
      packLoading: loading,
      series: saved?.series,
      mocks: saved?.mocks ?? const [],
      toeicLog: saved?.toeicLog ?? const {},
    );
  }

  static bool _isUntouched(TodayProgress t) =>
      t.done.isEmpty &&
      t.expressionKnown.isEmpty &&
      t.wordRatings.isEmpty &&
      t.spoken.isEmpty &&
      t.toeic.isEmpty &&
      t.quizAnswers.isEmpty;

  static TodayProgress _withPackId(TodayProgress t, String id) => t.copyWith(packId: id);

  static TodayProgress _carry(TodayProgress t, String date) => TodayProgress(
    date: date,
    done: t.done,
    expressionKnown: t.expressionKnown,
    wordRatings: t.wordRatings,
    spoken: t.spoken,
    quizAnswers: t.quizAnswers,
    packId: t.packId,
    cardsBefore: t.cardsBefore,
    selfGraded: t.selfGraded,
    carriedFrom: t.date,
    toeic: t.toeic,
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

  /// 받은 팩을 오늘 보여 줄 형태로 (처음 며칠은 분량을 줄이고 회상형 문제를 붙인다)
  static DailyPack _prepare(DailyPack raw, Map<String, DayRecord> log, DateTime now) =>
      prepareDailyPack(raw, dayNumber: dayNumberOf(log.keys, now));

  /// 서버에 보낼 팩 요청 (레벨·배운 것·복습 + 최근 주제·자주 틀리는 유형·주간 시리즈)
  Map<String, Object?> _requestFor(StudyState s, DateTime date) => buildPackRequest(
    date: date,
    profile: s.profile,
    contentStep: s.contentStep,
    learned: s.learned,
    cards: s.cards,
    recentTopics: recentTopicsOf(s.log, date),
    weakErrorTypes: weakErrorTypesOf(s.log, date),
    // 주제 지도에서 아직 안 다룬 상황을 제안한다 (서버는 참고만 한다)
    topicHint: topicHintFor(date, recentTopicsOf(s.log, date)).nameKo,
    series: s.series != null && s.series!.continuesOn(date) ? s.series : null,
    toeicTarget: s.settings.toeicTarget == null ? null : s.settings.target.label,
  );

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
      if (s0.packLoading) _set(s0.copyWith(packLoading: false, learned: registerLearned(s0.learned, s0.pack)));
      return;
    }
    if (s0.today.regenCount >= maxFetchPerDay) {
      _set(
        s0.copyWith(
          packLoading: false,
          packError: () => '오늘은 맞춤 학습을 충분히 만들었어요. 기본 학습으로 진행해요.',
          learned: registerLearned(s0.learned, s0.pack),
        ),
      );
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
      final json = await source.fetch(_requestFor(s0, s0.now));
      if (!ref.mounted || request != _packRequest) return; // 더 새 요청이 있다
      final parsed = _parsePack(json, state.learned, state.now);
      if (parsed == null) throw const PackFetchException('받은 학습 내용에 문제가 있어요.');
      final pack = _prepare(parsed, state.log, state.now);
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
          series: SeriesState.fromDialogue(pack.dialogue, state.now),
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
      final json = await source.fetch(_requestFor(s, tomorrow));
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
    Set<int>? selfGraded,
    Map<String, ToeicTaskRecord>? toeic,
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
      selfGraded: selfGraded ?? t.selfGraded,
      carriedFrom: t.carriedFrom,
      toeic: toeic ?? t.toeic,
    );
  }

  /// 오늘 루틴에서의 자가 평가. 평가를 바꾸면 '오늘 처음 평가하기 전 카드'에서 다시 계산해
  /// 여러 번 눌러도 단계가 계속 오르지 않게 한다.
  ({Map<String, ReviewCard> cards, Map<String, ReviewCard?> before}) _rateFromBaseline(String id, SelfRating rating) {
    // 예전에 이미 배운 기본 팩을 다시 보는 날은 복습 일정을 바꾸지 않는다 (같은 내용 반복으로 단계가 부풀지 않게)
    if (state.isRepeatPack) return (cards: state.cards, before: state.today.cardsBefore);
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

  /// 다시 말하면 더 높은 점수를 남긴다 (낮게 나온 재시도가 앞의 좋은 점수를 지우지 않게)
  void recordSpeaking(Sentence s, String heard) {
    final before = state.today.spoken[s.id];
    // 끝낸 말하기를 다시 하는 것은 연습: 점수는 바꾸지 않는다.
    // 다만 속으로만 따라 했던 문장을 저녁에 소리 내어 말한 것은 남긴다 (완료 기록은 이미 저장돼 바뀌지 않는다)
    if (state.done.contains(RoutineStep.speaking) && before != kSilentAttempt) return;
    if (before != null &&
        before != kSilentAttempt &&
        scoreSpeech(s.en, before).score >= scoreSpeech(s.en, heard).score) {
      return;
    }
    _set(state.copyWith(today: _progress(spoken: {...state.today.spoken, s.id: heard})));
  }

  /// 오늘 루틴의 토스 문항 결과를 남긴다. 다시 하면 더 높은 점수를 남긴다.
  /// 말하기 단계를 끝낸 뒤 다시 하는 것은 연습이라 기록을 바꾸지 않는다.
  void recordToeicTask(String id, ToeicTaskRecord r) {
    if (state.done.contains(RoutineStep.speaking)) return;
    final before = state.today.toeic[id];
    if (before != null && before.score >= r.score) return;
    _set(
      state.copyWith(
        today: _progress(toeic: {...state.today.toeic, id: r}),
        toeicLog: addDailyScore(state.toeicLog, state.today.carriedFrom ?? state.today.date, r.type, r.score),
      ),
    );
  }

  /// 모의고사 결과를 남긴다 (최근 30개)
  void recordMock(MockResult m) {
    final all = [...state.mocks, m];
    _set(state.copyWith(mocks: all.length > 30 ? all.sublist(all.length - 30) : all));
  }

  /// 토익스피킹 목표를 바꾼다. 표현·단어 난이도도 목표에 맞는 단계로 옮기고, 이후로는 평소처럼 자동 조정한다.
  void setToeicTarget(ToeicTarget target) {
    final s = state;
    if (s.settings.toeicTarget == target.score && s.contentStep == target.contentStep) return;
    _prefetchRequest++; // 옛 난이도로 받던 내일 팩은 저장하지 않는다
    final todayKey = dateKey(s.now);
    _set(
      s.copyWith(
        settings: s.settings.copyWith(toeicTarget: () => target.score),
        contentStep: target.contentStep,
        // 옛 난이도로 미리 받아 둔 내일 팩은 버린다 (오늘 팩·이어서 하는 팩은 그대로)
        packs: {
          for (final e in s.packs.entries)
            if (e.key.compareTo(todayKey) <= 0) e.key: e.value,
        },
      ),
    );
  }

  /// '목표 달성' 제안 닫기 (그 모의고사로는 다시 묻지 않는다)
  void dismissTargetSuggestion() {
    if (state.mocks.isEmpty) return;
    _set(state.copyWith(settings: state.settings.copyWith(toeicSuggestDismissed: () => mockKey(state.mocks.last))));
  }

  /// [selfGraded]: 회상형 문제를 쓰지 않고 '떠올렸어요'로 스스로 채점함 (복습 일정은 바꾸고 점수에서는 뺀다)
  void answerQuiz(int index, int choice, {bool selfGraded = false}) {
    if (state.quizAnswers.containsKey(index) || index >= state.pack.quiz.length) return;
    final item = state.pack.quiz[index];
    // 문제가 다루는 표현·단어의 복습 일정을 바꾼다
    // 어느 항목인지 모르는 문제는 복습 카드를 만들지 않는다 (복습에 나오지 않는 카드가 쌓이지 않게)
    final cardId = state.isRepeatPack ? null : item.itemId;
    final card = cardId == null ? null : state.cards[cardId] ?? ReviewCard.fresh(cardId, _today);
    // 퀴즈로 바뀌는 카드도 오늘 첫 상태를 남겨 둔다 (진행을 지울 때 함께 되돌리도록)
    final before = {...state.today.cardsBefore};
    if (cardId != null && !before.containsKey(cardId)) before[cardId] = state.cards[cardId];
    _set(
      state.copyWith(
        today: _progress(
          quizAnswers: {...state.quizAnswers, index: choice},
          cardsBefore: before,
          selfGraded: selfGraded ? {...state.today.selfGraded, index} : null,
        ),
        cards: card == null
            ? null
            : {...state.cards, cardId!: Srs.answer(card, correct: item.answerIndex == choice, today: _today)},
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

  /// 바쁜 날: 표현만 하고 오늘은 여기까지 (3분 루틴). 연속 기록은 이어지고 레벨·난이도는 그대로.
  /// 나중에 같은 날 전체 루틴을 끝내면 정식 기록으로 바뀐다.
  void finishMini() {
    final key = dateKey(_today);
    if (state.log.containsKey(key) || !state.done.contains(RoutineStep.expressions)) return;
    _set(
      state.copyWith(
        log: {
          ...state.log,
          key: DayRecord(accuracy: 0, levelScore: state.profile.overall.score, mini: true, topic: state.pack.topic),
        },
      ),
    );
    syncReminder();
  }

  /// 이어서 하던 지난 루틴을 그만두고 오늘 팩으로 새로 시작한다 (이미 평가한 표현·단어의 복습 일정은 그대로 둔다)
  void dropCarried() {
    if (state.today.carriedFrom == null) return;
    _set(state.copyWith(today: TodayProgress(date: state.today.date)));
    ref.invalidateSelf();
  }

  /// 오늘 3분 루틴으로만 기록한 상태
  bool get miniToday => state.log[dateKey(_today)]?.mini ?? false;

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
    // 기본 팩으로 하는 날(서버 없음)도 아직 시작 전이면 새 레벨에 맞는 기본 팩(A2 / B1)으로 바꾼다
    final swapFallback = dropToday || (untouched && !state.pack.fromClaude);
    final fallback = swapFallback
        ? _prepare(ref.read(fallbackPackProvider)(state.now, profile.overall.step), state.log, state.now)
        : null;
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
        // 새 팩을 받지 않고 바로 시작하는 팩은 지금 배운 항목으로 등록한다
        learned: dropToday ? null : registerLearned(state.learned, fallback ?? state.pack),
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

  /// 알림 예약·취소를 한 줄로 세운다 (켜고 끄는 요청이 겹쳐 껐는데도 예약되는 일이 없게).
  Future<void> _reminderQueue = Future.value();
  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _reminderQueue.then((_) => op());
    _reminderQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// 아침 알림을 켜거나(분) 끈다(null). 권한이 없어 예약하지 못하면 false.
  Future<bool> setReminder(int? minutes) => _serial(() => _setReminder(minutes));

  Future<bool> _setReminder(int? minutes) async {
    final reminder = ref.read(reminderProvider);
    if (minutes == null) {
      await reminder.cancel();
      if (!ref.mounted) return true;
      _set(state.copyWith(settings: state.settings.copyWith(reminderMinutes: () => null)));
      return true;
    }
    final ok = await reminder.schedule(_reminderPlan(minutes));
    if (!ref.mounted) return ok;
    if (ok) {
      ref.read(reminderBlockedProvider.notifier).set(false);
      _set(state.copyWith(settings: state.settings.copyWith(reminderMinutes: () => minutes)));
    }
    return ok;
  }

  /// 앱을 열 때·루틴을 끝냈을 때 알림 문구(연속 학습일)를 새로 고친다. 권한은 묻지 않는다.
  /// 휴대폰 설정에서 알림을 꺼 두었으면 [reminderBlockedProvider] 로 알린다.
  Future<void> syncReminder() => _serial(_syncReminder);

  Future<void> _syncReminder() async {
    if (!ref.mounted) return;
    // 줄을 기다리는 사이 알림을 껐을 수 있으므로 실행할 때의 설정을 본다
    final minutes = state.settings.reminderMinutes;
    if (minutes == null) return;
    final ok = await ref.read(reminderProvider).schedule(_reminderPlan(minutes), askPermission: false);
    if (ref.mounted) ref.read(reminderBlockedProvider.notifier).set(!ok);
  }

  /// 앞으로 7일 알림 계획 (오늘 끝냈으면 오늘은 건너뛰고, 날마다 연속 기록 상태에 맞는 문구)
  List<ReminderSlot> _reminderPlan(int minutes) {
    final s = state;
    return planReminders(
      now: ref.read(clockProvider)(),
      studyToday: s.now,
      minutes: minutes,
      doneToday: s.allDone || s.log.containsKey(dateKey(s.now)),
      streak: s.streakDays,
      restsLeft: s.streak.restsLeft,
      longest: s.longestStreak,
      teaser: (k) => reminderTeaser(s, k),
    );
  }

  void _finishDay() {
    final s = state;
    final quiz = s.pack.quiz;
    bool correctAt(int i) => s.quizAnswers[i] == quiz[i].answerIndex;
    // 고르는 문제만 정답률(난이도·레벨)에 쓰고, 직접 쓴 회상형 문제는 어휘 점수에 쓴다. 스스로 채점한 것은 빼고.
    final choiceIdx = [
      for (var i = 0; i < quiz.length; i++)
        if (!quiz[i].isRecall) i,
    ];
    final recallIdx = [
      for (var i = 0; i < quiz.length; i++)
        if (quiz[i].isRecall && s.quizAnswers.containsKey(i) && !s.today.selfGraded.contains(i)) i,
    ];
    final result = DailyResult(
      quizCorrect: choiceIdx.where(correctAt).length,
      quizTotal: choiceIdx.length,
      recallCorrect: recallIdx.where(correctAt).length,
      recallTotal: recallIdx.length,
      wordsKnown: s.wordRatings.values.where((r) => r == SelfRating.know).length,
      wordsTotal: s.pack.words.length,
      // 토스 말하기 결과가 있으면 그것으로, 없으면(예전 따라 말하기) 따라 말하기 점수로
      speakingAverage: s.toeicAverage ?? s.speakingAverage,
      expressionsAlreadyKnown: s.expressionKnown.values.where((k) => k).length,
      expressionsTotal: s.pack.expressions.length,
      reviewTotal: choiceIdx.where((i) => quiz[i].isReview).length,
      reviewCorrect: choiceIdx.where((i) => quiz[i].isReview && correctAt(i)).length,
    );
    // 틀린 고르는 문제의 오답 유형을 센다 (자주 틀리는 유형을 다음 팩에서 더 연습하게)
    final errors = <String, int>{};
    for (final i in choiceIdx) {
      final t = quiz[i].errorType;
      if (t != null && s.quizAnswers.containsKey(i) && !correctAt(i)) errors[t] = (errors[t] ?? 0) + 1;
    }
    final repeat = s.isRepeatPack;
    final adj = DailyAdjuster.adjust(
      profile: s.profile,
      currentContentStep: s.contentStep,
      today: result,
      yesterdayAccuracy: s.yesterdayAccuracy,
      date: s.now,
    );
    // 이미 배운 기본 팩을 다시 한 날은 기록만 남기고 레벨·난이도는 그대로 (아는 내용이라 정답률이 부풀어서)
    final profile = repeat ? s.profile : adj.profile;
    _set(
      s.copyWith(
        profile: profile,
        contentStep: repeat ? s.contentStep : adj.nextContentStep,
        // 점수 범위(0~1499) 끝에서 잘린 경우를 위해 실제로 바뀐 만큼을 기록한다
        today: _progress(levelDelta: profile.overall.score - s.profile.overall.score),
        log: {
          ...s.log,
          dateKey(_today): DayRecord(
            accuracy: result.accuracy,
            levelScore: profile.overall.score,
            speakingAverage: result.speakingAverage,
            newAccuracy: result.newAccuracy,
            // 완료 화면에는 쓰기 문제까지 모두 센 결과를 보여 준다
            quizCorrect: s.quizCorrect,
            quizTotal: quiz.length,
            topic: s.pack.topic,
            errors: errors,
          ),
        },
        lastAdjustmentReasons: repeat ? const ['오늘은 이미 배운 기본 학습을 다시 해서 레벨과 난이도는 그대로 둬요.'] : adj.reasons,
      ),
    );
  }
}

/// 알림에 넣을 표현: 오늘은 오늘 팩의 첫 표현, 내일은 미리 받은 팩의 첫 표현,
/// 그 뒤로는 배운 표현을 돌아가며 (다시 떠올리는 복습 효과). 없으면 null.
({String text, String meaning})? reminderTeaser(StudyState s, int dayOffset) {
  if (dayOffset == 0 && !s.allDone && s.pack.expressions.isNotEmpty) {
    final e = s.pack.expressions.first;
    return (text: e.pattern, meaning: e.meaning);
  }
  if (dayOffset == 1) {
    final key = dateKey(DateTime(s.now.year, s.now.month, s.now.day + 1));
    final raw = s.packs[key]?['expressions'];
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      final e = raw.first as Map;
      if (e['pattern'] is String && e['meaning'] is String) {
        return (text: e['pattern'] as String, meaning: e['meaning'] as String);
      }
    }
  }
  final learned =
      [
        for (final l in s.learned.values)
          if (l.kind == 'expression') l,
      ]..sort(
        (a, b) => a.firstSeen.compareTo(b.firstSeen) != 0 ? a.firstSeen.compareTo(b.firstSeen) : a.id.compareTo(b.id),
      );
  if (learned.isEmpty) return null;
  final l = learned[(dayOffset + s.now.day) % learned.length];
  return (text: l.text, meaning: l.meaning);
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
