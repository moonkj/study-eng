import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/level.dart';
import '../domain/srs.dart';
import '../domain/study_log.dart';
import 'pack_source.dart';

/// 복습 카드 저장 형식 (마지막 평가일까지 저장해야 '같은 날 재정답 무시'가 앱을 다시 켜도 유지된다)
Map<String, Object?> cardToJson(ReviewCard c) => {
  'stage': c.stage,
  'due': dateKey(c.due),
  'lapses': c.lapses,
  if (c.lastReviewed != null) 'last': dateKey(c.lastReviewed!),
};

ReviewCard cardFromJson(String id, Map<String, Object?> m) => ReviewCard(
  itemId: id,
  stage: (m['stage'] as num).toInt(),
  due: parseDateKey(m['due'] as String),
  lapses: (m['lapses'] as num).toInt(),
  lastReviewed: m['last'] == null ? null : parseDateKey(m['last'] as String),
);

/// 오늘 하루의 진행 상태 (날짜가 바뀌면 새로 시작)
class TodayProgress {
  const TodayProgress({
    required this.date,
    this.done = const {},
    this.expressionKnown = const {},
    this.wordRatings = const {},
    this.spoken = const {},
    this.quizAnswers = const {},
    this.levelDelta,
    this.packId,
    this.cardsBefore = const {},
    this.regenCount = 0,
  });

  final String date;

  /// 끝낸 루틴 단계 이름 (RoutineStep.name)
  final Set<String> done;
  final Map<String, bool> expressionKnown;
  final Map<String, SelfRating> wordRatings;

  /// 문장 id → 인식된 문장 (점수는 다시 계산할 수 있어 저장하지 않는다)
  final Map<String, String> spoken;
  final Map<int, int> quizAnswers;

  /// 루틴을 끝낸 뒤 얻은 레벨 점수
  final int? levelDelta;

  /// 오늘 진행이 어느 팩에 대한 것인지 (팩이 바뀌면 번호 기준 진행이 어긋나므로 버린다)
  final String? packId;

  /// 오늘 처음 평가하기 전의 카드 (null = 원래 없던 카드). 평가를 바꾸거나 되돌릴 때 기준이 된다.
  final Map<String, ReviewCard?> cardsBefore;

  /// 오늘 팩을 서버(Claude)에 요청한 횟수 (재시도·재진단 포함, 비용 상한용)
  final int regenCount;

  Map<String, Object?> toJson() => {
    'date': date,
    'done': done.toList(),
    'expressionKnown': expressionKnown,
    'wordRatings': wordRatings.map((k, v) => MapEntry(k, v.name)),
    'spoken': spoken,
    'quizAnswers': quizAnswers.map((k, v) => MapEntry('$k', v)),
    'levelDelta': levelDelta,
    'packId': packId,
    'cardsBefore': cardsBefore.map((k, c) => MapEntry(k, c == null ? null : cardToJson(c))),
    'regenCount': regenCount,
  };

  factory TodayProgress.fromJson(Map<String, Object?> j) => TodayProgress(
    date: j['date'] as String,
    done: {...(j['done'] as List).cast<String>()},
    expressionKnown: (j['expressionKnown'] as Map).cast<String, bool>(),
    wordRatings: (j['wordRatings'] as Map).map((k, v) => MapEntry(k as String, SelfRating.values.byName(v as String))),
    spoken: (j['spoken'] as Map).cast<String, String>(),
    quizAnswers: (j['quizAnswers'] as Map).map((k, v) => MapEntry(int.parse(k as String), (v as num).toInt())),
    levelDelta: (j['levelDelta'] as num?)?.toInt(),
    packId: j['packId'] as String?,
    cardsBefore: ((j['cardsBefore'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, v == null ? null : cardFromJson(k, (v as Map).cast<String, Object?>())),
    ),
    regenCount: (j['regenCount'] as num?)?.toInt() ?? 0,
  );
}

/// 사용자 설정
class AppSettings {
  const AppSettings({this.voice = 'en-US', this.speed = 1.0, this.reminderMinutes, this.reminderOffered = false});

  /// 발음 음성: en-US(미국) / en-GB(영국)
  final String voice;

  /// 듣기 속도 배율: 0.8 / 1.0 / 1.15
  final double speed;

  /// 아침 알림 시각(자정부터 분). null 이면 알림 끔
  final int? reminderMinutes;

  /// 첫 완료 때 알림 시각을 한 번 제안했는지 (매일 묻지 않게)
  final bool reminderOffered;

  AppSettings copyWith({String? voice, double? speed, int? Function()? reminderMinutes, bool? reminderOffered}) =>
      AppSettings(
        voice: voice ?? this.voice,
        speed: speed ?? this.speed,
        reminderMinutes: reminderMinutes == null ? this.reminderMinutes : reminderMinutes(),
        reminderOffered: reminderOffered ?? this.reminderOffered,
      );

  Map<String, Object?> toJson() => {
    'voice': voice,
    'speed': speed,
    'reminder': reminderMinutes,
    'reminderOffered': reminderOffered,
  };

  factory AppSettings.fromJson(Map<String, Object?>? j) => j == null
      ? const AppSettings()
      : AppSettings(
          voice: j['voice'] as String? ?? 'en-US',
          speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
          reminderMinutes: (j['reminder'] as num?)?.toInt(),
          reminderOffered: j['reminderOffered'] as bool? ?? false,
        );
}

/// 기기에 저장되는 전체 학습 데이터
class SavedData {
  const SavedData({
    required this.profile,
    required this.contentStep,
    required this.onboarded,
    this.log = const {},
    this.cards = const {},
    this.today,
    this.lastReasons = const [],
    this.packs = const {},
    this.learned = const {},
    this.settings = const AppSettings(),
  });

  final LearnerProfile profile;
  final int contentStep;

  /// 레벨 진단(또는 건너뛰기)을 마쳤는지
  final bool onboarded;
  final Map<String, DayRecord> log;
  final Map<String, ReviewCard> cards;
  final TodayProgress? today;
  final List<String> lastReasons;

  /// 받아 둔 학습 팩 (날짜 → 서버 응답 JSON). 오늘과 내일 것만 남긴다.
  final Map<String, Map<String, Object?>> packs;

  /// 지금까지 배운 표현·단어
  final Map<String, LearnedItem> learned;
  final AppSettings settings;

  static const version = 1;

  Map<String, Object?> toJson() => {
    'v': version,
    'profile': {'overall': profile.overall.score, 'skills': profile.skills.map((k, v) => MapEntry(k.name, v.score))},
    'contentStep': contentStep,
    'onboarded': onboarded,
    'log': log.map((k, v) => MapEntry(k, v.toJson())),
    'cards': cards.map((k, c) => MapEntry(k, cardToJson(c))),
    'today': today?.toJson(),
    'lastReasons': lastReasons,
    'packs': packs,
    'learned': learned.map((k, v) => MapEntry(k, v.toJson())),
    'settings': settings.toJson(),
  };

  /// 섹션별로 따로 읽는다. 기록·카드·팩 중 하나가 깨져도 나머지(특히 레벨과 연속 기록)는 살린다.
  /// 레벨·진단 여부 같은 핵심 값이 깨졌을 때만 예외를 던진다.
  factory SavedData.fromJson(Map<String, Object?> j) {
    T section<T>(T Function() read, T fallback) {
      try {
        return read();
      } catch (_) {
        return fallback;
      }
    }

    final p = j['profile'] as Map<String, Object?>;
    final overall = Level((p['overall'] as num).toInt());
    return SavedData(
      profile: LearnerProfile(
        overall: overall,
        skills: section(
          () => {
            for (final e in (p['skills'] as Map).entries)
              Skill.values.byName(e.key as String): Level((e.value as num).toInt()),
          },
          {for (final s in Skill.values) s: overall},
        ),
      ),
      contentStep: section(() => (j['contentStep'] as num).toInt(), overall.step),
      onboarded: j['onboarded'] as bool,
      log: section(
        () => (j['log'] as Map).map((k, v) => MapEntry(k as String, DayRecord.fromJson((v as Map).cast()))),
        const {},
      ),
      cards: section(() {
        final cards = <String, ReviewCard>{};
        for (final e in (j['cards'] as Map).entries) {
          try {
            cards[e.key as String] = cardFromJson(e.key as String, (e.value as Map).cast<String, Object?>());
          } catch (_) {
            // 카드 하나가 깨졌으면 그 카드만 버린다
          }
        }
        return cards;
      }, const {}),
      today: section(() => j['today'] == null ? null : TodayProgress.fromJson((j['today'] as Map).cast()), null),
      lastReasons: section(() => (j['lastReasons'] as List).cast<String>(), const []),
      packs: section(
        () =>
            ((j['packs'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as Map).cast<String, Object?>())),
        const {},
      ),
      learned: section(
        () => ((j['learned'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, LearnedItem.fromJson(k, (v as Map).cast())),
        ),
        const {},
      ),
      settings: section(
        () => AppSettings.fromJson((j['settings'] as Map?)?.cast<String, Object?>()),
        const AppSettings(),
      ),
    );
  }
}

/// 저장소 인터페이스. 나중에 Drift 등으로 바꿔도 화면 코드는 그대로 둔다.
abstract class AppStore {
  SavedData? load();
  Future<void> save(SavedData data);
}

class PrefsStore implements AppStore {
  PrefsStore(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'todaye.v1';

  @override
  SavedData? load() {
    final String? raw;
    try {
      raw = _prefs.getString(_key);
    } catch (_) {
      // 문자열이 아닌 값이 들어 있으면(외부 도구로 건드린 경우 등) 처음부터 시작한다
      _prefs.remove(_key);
      return null;
    }
    if (raw == null) return null;
    try {
      return SavedData.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // 핵심 값이 깨졌으면 처음부터 시작한다. 원본은 시각을 붙인 백업 키에 남겨 덮어쓰지 않는다.
      // 백업은 최신 하나만 남기고(쌓이지 않게), 깨진 원본은 지운다
      _prefs.setString('$_key.corrupt', raw);
      _prefs.remove(_key);
      return null;
    }
  }

  @override
  Future<void> save(SavedData data) async {
    try {
      await _prefs.setString(_key, jsonEncode(data.toJson()));
    } catch (e) {
      // 저장 공간 부족 등: 앱은 계속 쓰고, 다음 저장 때 다시 시도한다.
      assert(() {
        debugPrint('todaye: 저장 실패 $e');
        return true;
      }());
    }
  }
}

class MemoryStore implements AppStore {
  MemoryStore([this.data]);
  SavedData? data;

  @override
  SavedData? load() => data == null ? null : SavedData.fromJson(jsonDecode(jsonEncode(data!.toJson())));

  @override
  Future<void> save(SavedData d) async => data = d;
}

/// main()에서 실제 저장소로 덮어쓴다.
final storeProvider = Provider<AppStore>((ref) => MemoryStore());
