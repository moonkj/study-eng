import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/sample_content.dart';
import '../domain/daily_adjuster.dart';
import '../domain/level.dart';
import '../domain/speech_score.dart';
import '../domain/srs.dart';

/// 오늘의 루틴 4단계
enum RoutineStep { expressions, words, speaking, quiz }

/// 테스트에서 날짜를 고정할 수 있도록 시계를 주입한다.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class StudyState {
  const StudyState({
    required this.pack,
    required this.profile,
    required this.contentStep,
    required this.streakDays,
    required this.studiedDays,
    this.done = const {},
    this.expressionKnown = const {},
    this.wordRatings = const {},
    this.speaking = const {},
    this.quizAnswers = const {},
    this.cards = const {},
    this.yesterdayAccuracy,
    this.adjustment,
    this.lastAdjustmentReasons = const [],
  });

  final DailyPack pack;
  final LearnerProfile profile;
  final int contentStep;
  final int streakDays;

  /// 이번 달 학습한 날짜(일)
  final Set<int> studiedDays;
  final Set<RoutineStep> done;
  final Map<String, bool> expressionKnown;
  final Map<String, SelfRating> wordRatings;
  final Map<String, SpeechScore> speaking;
  final Map<int, int> quizAnswers;
  final Map<String, ReviewCard> cards;
  final double? yesterdayAccuracy;

  /// 오늘 루틴을 끝내면 계산되는 내일 계획
  final DailyAdjustment? adjustment;
  final List<String> lastAdjustmentReasons;

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
    int? streakDays,
    Set<int>? studiedDays,
    Set<RoutineStep>? done,
    Map<String, bool>? expressionKnown,
    Map<String, SelfRating>? wordRatings,
    Map<String, SpeechScore>? speaking,
    Map<int, int>? quizAnswers,
    Map<String, ReviewCard>? cards,
    DailyAdjustment? adjustment,
    List<String>? lastAdjustmentReasons,
  }) {
    return StudyState(
      pack: pack,
      profile: profile ?? this.profile,
      contentStep: contentStep ?? this.contentStep,
      streakDays: streakDays ?? this.streakDays,
      studiedDays: studiedDays ?? this.studiedDays,
      done: done ?? this.done,
      expressionKnown: expressionKnown ?? this.expressionKnown,
      wordRatings: wordRatings ?? this.wordRatings,
      speaking: speaking ?? this.speaking,
      quizAnswers: quizAnswers ?? this.quizAnswers,
      cards: cards ?? this.cards,
      yesterdayAccuracy: yesterdayAccuracy,
      adjustment: adjustment ?? this.adjustment,
      lastAdjustmentReasons: lastAdjustmentReasons ?? this.lastAdjustmentReasons,
    );
  }
}

/// 개발용 초기 프로필 (첫 진단 전 기본값: B1.2)
LearnerProfile initialProfile() => const LearnerProfile(
  overall: Level(764),
  skills: {
    Skill.vocabulary: Level(980),
    Skill.grammar: Level(720),
    Skill.listening: Level(700),
    Skill.speaking: Level(430),
  },
);

class StudyController extends Notifier<StudyState> {
  @override
  StudyState build() {
    final now = ref.read(clockProvider)();
    return StudyState(
      pack: samplePack(now),
      profile: initialProfile(),
      contentStep: 7,
      streakDays: 12,
      studiedDays: {
        for (var d = 1; d < now.day; d++)
          if (d != 4 && d != 10) d,
      },
      yesterdayAccuracy: 0.88,
      lastAdjustmentReasons: const ['퀴즈 정답률 88% → 표현 난이도 한 단계 올렸어요', '말하기 점수가 낮아 말하기 문장을 10개 → 12개로'],
    );
  }

  DateTime get _today => ref.read(clockProvider)();

  void setExpressionKnown(String id, bool known) {
    state = state.copyWith(expressionKnown: {...state.expressionKnown, id: known});
  }

  void rateWord(String id, SelfRating rating) {
    final card = state.cards[id] ?? ReviewCard.fresh(id, _today);
    state = state.copyWith(
      wordRatings: {...state.wordRatings, id: rating},
      cards: {...state.cards, id: Srs.rate(card, rating, _today)},
    );
  }

  void recordSpeaking(Sentence s, String heard) {
    state = state.copyWith(speaking: {...state.speaking, s.id: scoreSpeech(s.en, heard)});
  }

  void answerQuiz(int index, int choice) {
    if (state.quizAnswers.containsKey(index)) return;
    final item = state.pack.quiz[index];
    final card = state.cards[item.id] ?? ReviewCard.fresh(item.id, _today);
    state = state.copyWith(
      quizAnswers: {...state.quizAnswers, index: choice},
      cards: {
        ...state.cards,
        item.id: Srs.answer(card, correct: item.answerIndex == choice, today: _today),
      },
    );
  }

  void complete(RoutineStep step) {
    if (state.done.contains(step)) return;
    final done = {...state.done, step};
    state = state.copyWith(done: done);
    if (state.allDone) _finishDay();
  }

  void applyLevelTest(LearnerProfile profile) {
    state = state.copyWith(profile: profile, contentStep: profile.overall.step);
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
    );
    final adj = DailyAdjuster.adjust(
      profile: s.profile,
      currentContentStep: s.contentStep,
      today: result,
      yesterdayAccuracy: s.yesterdayAccuracy,
    );
    state = s.copyWith(
      adjustment: adj,
      profile: adj.profile,
      contentStep: adj.nextContentStep,
      streakDays: s.streakDays + 1,
      studiedDays: {...s.studiedDays, _today.day},
      lastAdjustmentReasons: adj.reasons,
    );
  }
}

final studyProvider = NotifierProvider<StudyController, StudyState>(StudyController.new);
