import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/data/store.dart';
import 'package:todaye/data/sync.dart';
import 'package:todaye/domain/level.dart';
import 'package:todaye/domain/study_log.dart';
import 'package:todaye/domain/toeic_feedback.dart';
import 'package:todaye/domain/toeic_weakness.dart';

/// 서버 흉내: 버전이 맞을 때만 저장한다
class FakeServer implements SyncClient {
  int version = 0;
  String? data;
  bool offline = false;

  @override
  Future<SyncDoc> get() async {
    if (offline) throw StateError('offline');
    return SyncDoc(version, data);
  }

  @override
  Future<int> put(String d, int baseVersion) async {
    if (offline) throw StateError('offline');
    if (baseVersion != version) throw SyncConflict(SyncDoc(version, data));
    data = d;
    return ++version;
  }

  SavedData? get saved => data == null ? null : SavedData.fromJson((jsonDecode(data!) as Map).cast());
}

LearnerProfile _profile(int step) =>
    LearnerProfile(overall: Level.fromStep(step), skills: {for (final s in Skill.values) s: Level.fromStep(step)});

SavedData _data({
  int step = 7,
  Map<String, DayRecord> log = const {},
  TodayProgress? today,
  int? updatedAt,
  List<MockResult> mocks = const [],
  ToeicLog toeicLog = const {},
}) => SavedData(
  profile: _profile(step),
  contentStep: step,
  onboarded: true,
  log: log,
  today: today,
  updatedAt: updatedAt,
  mocks: mocks,
  toeicLog: toeicLog,
);

const _day = DayRecord(accuracy: 0.8, levelScore: 700);
const _mini = DayRecord(accuracy: 0, levelScore: 700, mini: true);

void main() {
  group('합치기', () {
    test('쌓이는 기록은 양쪽을 모두 남기고, 하나뿐인 값은 최근에 저장한 쪽을 따른다', () {
      final phone = _data(
        step: 8,
        log: {'2026-11-24': _day, '2026-11-25': _mini},
        today: const TodayProgress(date: '2026-11-25'),
        updatedAt: 2000,
        toeicLog: const {
          '2026-11-25': {'info': ToeicDayScore(first: 40, best: 40)},
        },
      );
      final pad = _data(
        step: 7,
        log: {'2026-11-23': _day, '2026-11-25': _day},
        today: const TodayProgress(date: '2026-11-24'),
        updatedAt: 1000,
        toeicLog: const {
          '2026-11-25': {'info': ToeicDayScore(first: 55, best: 60), 'picture': ToeicDayScore(first: 50, best: 50)},
        },
        mocks: const [MockResult(date: '2026-11-20', level: 'IM2', target: 'IM3')],
      );
      final m = mergeSaved(pad, phone);
      expect(m.contentStep, 8); // 최근 저장한 아이폰
      expect(m.log.keys.toSet(), {'2026-11-23', '2026-11-24', '2026-11-25'});
      expect(m.log['2026-11-25']!.mini, isFalse); // 정식 기록 우선
      expect(m.today!.date, '2026-11-25');
      // 첫 시도는 최근 저장한 쪽(아이폰 40), 최고 점수는 높은 쪽(아이패드 60)
      expect(m.toeicLog['2026-11-25'], {
        'info': const ToeicDayScore(first: 40, best: 60),
        'picture': const ToeicDayScore(first: 50, best: 50),
      });
      expect(m.mocks.length, 1);
      expect(m.updatedAt, 2000);
      expect(mergeSaved(phone, pad).contentStep, 8); // 순서와 상관없이 같은 결과
    });

    test('아직 동기화한 적 없는 새 기기의 빈 데이터가 기록 많은 쪽을 덮어쓰지 않는다', () {
      final phone = _data(step: 9, log: {'2026-11-20': _day, '2026-11-21': _day});
      final pad = _data(step: 6, updatedAt: 5000);
      expect(mergeSaved(pad, phone).contentStep, 9);
    });
  });

  test('처음 연동하는 기기는 서버(동기화된) 기록을 따른다, 학습한 날이 더 많을 때만 자기 것', () {
    final synced = _data(step: 8, updatedAt: 1000);
    final fresh = _data(step: 6);
    expect(mergeSaved(fresh, synced).contentStep, 8);
    expect(mergeSaved(synced, fresh).contentStep, 8);
    final richer = _data(step: 6, log: {'2026-11-20': _day});
    expect(mergeSaved(richer, synced).contentStep, 6);
  });

  group('동기화 저장소', () {
    test('처음 켠 기기는 자기 기록을 올리고, 다른 기기는 켤 때 받아 합친다', () async {
      final server = FakeServer();
      final phoneLocal = MemoryStore(_data(step: 8, log: {'2026-11-23': _day, '2026-11-24': _day}));
      final phone = SyncedStore(phoneLocal, server, MemorySyncMeta(), now: () => DateTime(2026, 11, 25, 9));
      await phone.pull();
      expect(server.version, 1);
      expect(server.saved!.log.containsKey('2026-11-24'), isTrue);

      final padLocal = MemoryStore(_data(step: 6, log: {'2026-11-22': _day}));
      final pad = SyncedStore(padLocal, server, MemorySyncMeta(), now: () => DateTime(2026, 11, 25, 10));
      var notified = 0;
      pad.onRemoteChange = () => notified++;
      expect(await pad.pull(), isTrue);
      expect(notified, 1);
      final onPad = padLocal.load()!;
      expect(onPad.contentStep, 8);
      expect(onPad.log.keys.toSet(), {'2026-11-22', '2026-11-23', '2026-11-24'});
      // 아이패드에만 있던 기록도 서버에 올라간다
      expect(server.saved!.log.containsKey('2026-11-22'), isTrue);
    });

    test('저장하면 잠시 뒤 올리고, 다른 기기가 먼저 올렸으면 합쳐서 다시 올린다', () async {
      final server = FakeServer();
      final a = SyncedStore(
        MemoryStore(_data()),
        server,
        MemorySyncMeta(),
        debounce: Duration.zero,
        now: () => DateTime(2026, 11, 25, 9),
      );
      final b = SyncedStore(
        MemoryStore(_data()),
        server,
        MemorySyncMeta(),
        debounce: Duration.zero,
        now: () => DateTime(2026, 11, 25, 10),
      );
      await a.pull();
      await b.pull();
      await a.save(_data(log: {'2026-11-24': _day}));
      await a.flush();
      await b.save(_data(log: {'2026-11-25': _day}));
      await b.flush(); // 버전이 어긋나 409 → 합쳐서 다시
      expect(server.saved!.log.keys.toSet(), {'2026-11-24', '2026-11-25'});
      expect(b.load()!.log.keys.toSet(), {'2026-11-24', '2026-11-25'});
      // a 는 앱으로 돌아올 때 받는다
      expect(await a.pull(), isTrue);
      expect(a.load()!.log.keys.toSet(), {'2026-11-24', '2026-11-25'});
    });

    test('서버에 닿지 못해도 기기에는 저장되고, 다음에 다시 올린다', () async {
      final server = FakeServer()..offline = true;
      final local = MemoryStore(_data());
      final s = SyncedStore(local, server, MemorySyncMeta(), debounce: Duration.zero);
      await s.save(_data(log: {'2026-11-25': _day}));
      await s.flush();
      expect(local.load()!.log.containsKey('2026-11-25'), isTrue);
      expect(server.version, 0);
      server.offline = false;
      await s.flush();
      expect(server.saved!.log.containsKey('2026-11-25'), isTrue);
    });

    test('동기화 주소는 학습 팩 주소에서 만든다', () {
      expect(syncUrlFor('https://x.net/dailyPack'), 'https://x.net/sync');
      expect(syncUrlFor(''), isNull);
    });
  });
}
