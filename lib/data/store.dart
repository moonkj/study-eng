import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/level.dart';
import '../domain/srs.dart';
import '../domain/study_log.dart';

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

  Map<String, Object?> toJson() => {
    'date': date,
    'done': done.toList(),
    'expressionKnown': expressionKnown,
    'wordRatings': wordRatings.map((k, v) => MapEntry(k, v.name)),
    'spoken': spoken,
    'quizAnswers': quizAnswers.map((k, v) => MapEntry('$k', v)),
    'levelDelta': levelDelta,
  };

  factory TodayProgress.fromJson(Map<String, Object?> j) => TodayProgress(
    date: j['date'] as String,
    done: {...(j['done'] as List).cast<String>()},
    expressionKnown: (j['expressionKnown'] as Map).cast<String, bool>(),
    wordRatings: (j['wordRatings'] as Map).map((k, v) => MapEntry(k as String, SelfRating.values.byName(v as String))),
    spoken: (j['spoken'] as Map).cast<String, String>(),
    quizAnswers: (j['quizAnswers'] as Map).map((k, v) => MapEntry(int.parse(k as String), (v as num).toInt())),
    levelDelta: (j['levelDelta'] as num?)?.toInt(),
  );
}

/// 사용자 설정
class AppSettings {
  const AppSettings({this.voice = 'en-US', this.speed = 1.0, this.reminderMinutes});

  /// 발음 음성: en-US(미국) / en-GB(영국)
  final String voice;

  /// 듣기 속도 배율: 0.8 / 1.0 / 1.15
  final double speed;

  /// 아침 알림 시각(자정부터 분). null 이면 알림 끔
  final int? reminderMinutes;

  AppSettings copyWith({String? voice, double? speed, int? Function()? reminderMinutes}) => AppSettings(
    voice: voice ?? this.voice,
    speed: speed ?? this.speed,
    reminderMinutes: reminderMinutes == null ? this.reminderMinutes : reminderMinutes(),
  );

  Map<String, Object?> toJson() => {'voice': voice, 'speed': speed, 'reminder': reminderMinutes};

  factory AppSettings.fromJson(Map<String, Object?>? j) => j == null
      ? const AppSettings()
      : AppSettings(
          voice: j['voice'] as String? ?? 'en-US',
          speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
          reminderMinutes: (j['reminder'] as num?)?.toInt(),
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
    this.packJson,
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

  /// 오늘 받은 학습 팩 (다시 생성하지 않도록 저장)
  final Map<String, Object?>? packJson;
  final AppSettings settings;

  static const version = 1;

  Map<String, Object?> toJson() => {
    'v': version,
    'profile': {'overall': profile.overall.score, 'skills': profile.skills.map((k, v) => MapEntry(k.name, v.score))},
    'contentStep': contentStep,
    'onboarded': onboarded,
    'log': log.map((k, v) => MapEntry(k, v.toJson())),
    'cards': cards.map((k, c) => MapEntry(k, {'stage': c.stage, 'due': dateKey(c.due), 'lapses': c.lapses})),
    'today': today?.toJson(),
    'lastReasons': lastReasons,
    'pack': packJson,
    'settings': settings.toJson(),
  };

  factory SavedData.fromJson(Map<String, Object?> j) {
    final p = j['profile'] as Map<String, Object?>;
    return SavedData(
      profile: LearnerProfile(
        overall: Level((p['overall'] as num).toInt()),
        skills: {
          for (final e in (p['skills'] as Map).entries)
            Skill.values.byName(e.key as String): Level((e.value as num).toInt()),
        },
      ),
      contentStep: (j['contentStep'] as num).toInt(),
      onboarded: j['onboarded'] as bool,
      log: (j['log'] as Map).map((k, v) => MapEntry(k as String, DayRecord.fromJson((v as Map).cast()))),
      cards: (j['cards'] as Map).map((k, v) {
        final m = (v as Map).cast<String, Object?>();
        return MapEntry(
          k as String,
          ReviewCard(
            itemId: k,
            stage: (m['stage'] as num).toInt(),
            due: parseDateKey(m['due'] as String),
            lapses: (m['lapses'] as num).toInt(),
          ),
        );
      }),
      today: j['today'] == null ? null : TodayProgress.fromJson((j['today'] as Map).cast()),
      lastReasons: (j['lastReasons'] as List).cast<String>(),
      packJson: (j['pack'] as Map?)?.cast<String, Object?>(),
      settings: AppSettings.fromJson((j['settings'] as Map?)?.cast<String, Object?>()),
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
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return SavedData.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // 저장 형식이 깨졌으면 처음부터 시작한다 (원본은 백업 키에 남긴다)
      _prefs.setString('$_key.corrupt', raw);
      return null;
    }
  }

  @override
  Future<void> save(SavedData data) => _prefs.setString(_key, jsonEncode(data.toJson()));
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
