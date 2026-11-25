import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/toeic_feedback.dart' show MockResult, mockKey;
import 'store.dart';

// ───────────────────────── 합치기 ─────────────────────────

/// 두 기기의 저장 데이터를 합친다.
/// - 쌓이는 기록(하루 기록·배운 항목·복습 카드·팩·모의고사·토스 점수)은 양쪽을 모두 남긴다.
/// - 하나만 남길 수 있는 값(레벨·설정·오늘 진행 등)은 더 최근에 저장한 쪽을 따른다.
///   한쪽이 아직 동기화한 적 없는 예전 데이터면(저장 시각 없음) 기록이 더 많은 쪽을 따른다.
SavedData mergeSaved(SavedData a, SavedData b) {
  final aFirst = _prefer(a, b);
  final base = aFirst ? a : b;
  final other = aFirst ? b : a;

  final log = {...other.log, ...base.log};
  for (final e in other.log.entries) {
    final mine = base.log[e.key];
    // 같은 날: 정식 기록이 3분 루틴 기록보다 우선
    if (mine != null && mine.mini && !e.value.mini) log[e.key] = e.value;
  }

  final mocks = <String, MockResult>{
    for (final m in [...other.mocks, ...base.mocks]) mockKey(m): m,
  }.values.toList()..sort((x, y) => x.date.compareTo(y.date));

  final toeicLog = <String, Map<String, int>>{};
  for (final src in [other.toeicLog, base.toeicLog]) {
    for (final day in src.entries) {
      final merged = toeicLog[day.key] = {...?toeicLog[day.key]};
      for (final t in day.value.entries) {
        final before = merged[t.key];
        if (before == null || t.value > before) merged[t.key] = t.value;
      }
    }
  }

  // 오늘 진행: 더 늦은 날짜, 같은 날이면 최근 쪽
  final today = switch ((base.today, other.today)) {
    (final x?, final y?) => y.date.compareTo(x.date) > 0 ? y : x,
    (final x, final y) => x ?? y,
  };

  final times = [a.updatedAt, b.updatedAt].whereType<int>();
  return base.copyWith(
    onboarded: a.onboarded || b.onboarded,
    log: log,
    cards: {...other.cards, ...base.cards},
    learned: {...other.learned, ...base.learned},
    packs: {...other.packs, ...base.packs},
    mocks: mocks.length > 30 ? mocks.sublist(mocks.length - 30) : mocks,
    toeicLog: toeicLog,
    today: () => today,
    updatedAt: times.isEmpty ? null : times.reduce((x, y) => x > y ? x : y),
  );
}

/// a 를 기준으로 삼을지
bool _prefer(SavedData a, SavedData b) {
  if (!b.onboarded && a.onboarded) return true;
  if (!a.onboarded && b.onboarded) return false;
  final ta = a.updatedAt, tb = b.updatedAt;
  if (ta != null && tb != null) return ta >= tb;
  // 한쪽만 동기화된 데이터면(처음 연동하는 기기) 동기화된 쪽을 따른다. 처음 기기에 학습한 날이 더 많을 때만 그쪽
  if (ta != null && tb == null) return b.log.length <= a.log.length;
  if (tb != null && ta == null) return !(a.log.length <= b.log.length);
  // 아직 동기화한 적 없는 데이터가 섞이면 기록이 많은 쪽 (새 기기의 빈 데이터가 덮어쓰지 않게)
  final la = a.log.length + a.learned.length, lb = b.log.length + b.learned.length;
  if (la != lb) return la > lb;
  return (ta ?? 0) >= (tb ?? 0);
}

// ───────────────────────── 서버 ─────────────────────────

class SyncDoc {
  const SyncDoc(this.version, this.data);
  final int version;

  /// 저장 JSON 문자열 (서버가 비었으면 null)
  final String? data;
}

class SyncConflict implements Exception {
  const SyncConflict(this.current);
  final SyncDoc current;
}

abstract class SyncClient {
  Future<SyncDoc> get();

  /// 서버 버전이 [baseVersion] 일 때만 저장하고 새 버전을 돌려준다. 다른 기기가 먼저 바꿨으면 [SyncConflict]
  Future<int> put(String data, int baseVersion);
}

class RemoteSyncClient implements SyncClient {
  RemoteSyncClient({required this.url, required this.token, http.Client? client}) : _http = client ?? http.Client();
  final String url;
  final String token;
  final http.Client _http;

  Future<(int, Map)> _post(Map<String, Object?> body) async {
    final res = await _http
        .post(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map) throw const FormatException('sync: 응답 형식');
    return (res.statusCode, json);
  }

  static SyncDoc _doc(Map j) => SyncDoc((j['version'] as num?)?.toInt() ?? 0, j['data'] as String?);

  @override
  Future<SyncDoc> get() async {
    final (status, j) = await _post({'op': 'get'});
    if (status != 200) throw StateError('sync get $status');
    return _doc(j);
  }

  @override
  Future<int> put(String data, int baseVersion) async {
    final (status, j) = await _post({'op': 'put', 'baseVersion': baseVersion, 'data': data});
    if (status == 409) throw SyncConflict(_doc(j));
    if (status != 200) throw StateError('sync put $status');
    return (j['version'] as num).toInt();
  }
}

/// 동기화 주소는 학습 팩 주소에서 만든다 (…/dailyPack → …/sync)
String? syncUrlFor(String packUrl) {
  if (packUrl.isEmpty) return null;
  final u = packUrl.replaceFirst(RegExp(r'/dailyPack/?$'), '/sync');
  return u == packUrl ? null : u;
}

// ───────────────────────── 저장소 ─────────────────────────

/// 이 기기가 마지막으로 맞춘 서버 버전
abstract class SyncMeta {
  int get version;
  set version(int v);
}

class PrefsSyncMeta implements SyncMeta {
  PrefsSyncMeta(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'todaye.syncVersion';

  @override
  int get version => _prefs.getInt(_key) ?? 0;

  @override
  set version(int v) => _prefs.setInt(_key, v);
}

class MemorySyncMeta implements SyncMeta {
  @override
  int version = 0;
}

/// 기기 저장소에 저장하고, 잠시 뒤 서버에도 올린다. 서버에 다른 기기의 새 기록이 있으면 합쳐서 받는다.
/// 서버에 닿지 못해도 앱은 기기 저장소로 그대로 쓰고, 다음 저장·앱 복귀 때 다시 맞춘다.
class SyncedStore implements AppStore {
  SyncedStore(
    this.inner,
    this.client,
    this.meta, {
    this.debounce = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppStore inner;
  final SyncClient client;
  final SyncMeta meta;
  final Duration debounce;
  final DateTime Function() _now;

  /// 다른 기기의 기록을 합쳐 기기 저장소가 바뀌었을 때 (화면 상태를 저장소에서 다시 읽게 한다)
  void Function()? get onRemoteChange => _onRemoteChange;
  set onRemoteChange(void Function()? f) {
    _onRemoteChange = f;
    // 화면이 뜨기 전에 받은 변경이 있으면 바로 알린다
    if (f != null && _missed) {
      _missed = false;
      f();
    }
  }

  void Function()? _onRemoteChange;
  bool _missed = false;

  void clearMissed() => _missed = false;

  void _notify() {
    final f = _onRemoteChange;
    if (f == null) {
      _missed = true;
    } else {
      f();
    }
  }

  Timer? _timer;
  bool _dirty = false;
  Future<void> _queue = Future.value();

  @override
  SavedData? load() => inner.load();

  @override
  Future<void> save(SavedData data) async {
    await inner.save(data.copyWith(updatedAt: _now().millisecondsSinceEpoch));
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(push()));
  }

  /// 기다리지 않고 바로 올린다 (앱이 백그라운드로 갈 때)
  Future<void> flush() {
    _timer?.cancel();
    return push();
  }

  /// 차례로 실행 (올리기·받기가 겹치지 않게)
  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  SavedData? _parse(String? raw) {
    if (raw == null) return null;
    try {
      return SavedData.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  String _encode(SavedData d) => jsonEncode(d.toJson());

  /// 합친 결과를 기기에 저장하고, 기기 데이터가 바뀌었으면 알린다
  Future<void> _adopt(SavedData? local, SavedData merged) async {
    await inner.save(merged);
    if (local == null || _encode(local) != _encode(merged)) _notify();
  }

  Future<void> push() => _serial(() async {
    if (!_dirty) return;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        var local = inner.load();
        if (local == null) return;
        // 서버에 올리는 데이터에는 항상 저장 시각을 붙인다 (다른 기기가 합칠 때 기준이 된다)
        if (local.updatedAt == null) {
          local = local.copyWith(updatedAt: _now().millisecondsSinceEpoch);
          await inner.save(local);
        }
        _dirty = false;
        try {
          meta.version = await client.put(_encode(local), meta.version);
          return;
        } on SyncConflict catch (c) {
          // 다른 기기가 먼저 올렸다: 합쳐서 다시 올린다
          final remote = _parse(c.current.data);
          final merged = remote == null ? local : mergeSaved(local, remote);
          meta.version = c.current.version;
          await _adopt(local, merged);
          _dirty = true;
        }
      }
    } catch (_) {
      _dirty = true; // 연결 실패: 다음에 다시
    }
  });

  /// 서버의 새 기록을 받아 합친다. 기기 데이터가 바뀌었으면 true
  Future<bool> pull() async {
    final changed = await _serial(() async {
      final doc = await client.get();
      final local = inner.load();
      if (doc.version == meta.version) {
        // 서버가 비어 있으면 이 기기 기록을 처음으로 올린다
        if (doc.version == 0 && local != null) _dirty = true;
        return false;
      }
      final remote = _parse(doc.data);
      meta.version = doc.version;
      if (remote == null) {
        if (local != null) _dirty = true;
        return false;
      }
      final merged = local == null ? remote : mergeSaved(local, remote);
      await inner.save(merged);
      // 이 기기에만 있던 기록이 있으면 서버에도 올린다
      if (_encode(merged) != _encode(remote)) _dirty = true;
      return local == null || _encode(local) != _encode(merged);
    });
    if (_dirty) await push();
    if (changed) _notify();
    return changed;
  }
}
