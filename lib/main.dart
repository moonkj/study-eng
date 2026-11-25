import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'data/pack_source.dart' show contentApiUrl, contentApiToken;
import 'data/store.dart';
import 'data/sync.dart';
import 'data/toeic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 저장소를 열지 못해도(파일 손상 등) 앱은 켜지게: 이번 실행은 메모리에만 저장한다
  AppStore store;
  try {
    final prefs = await SharedPreferences.getInstance();
    store = PrefsStore(prefs);
    // 아이폰·아이패드 기록 맞추기: 서버 주소가 있으면 켜기 전에 다른 기기의 기록을 받아 합친다 (오래 걸리면 기다리지 않는다)
    final syncUrl = syncUrlFor(contentApiUrl);
    if (syncUrl != null && contentApiToken.isNotEmpty) {
      final synced = SyncedStore(store, RemoteSyncClient(url: syncUrl, token: contentApiToken), PrefsSyncMeta(prefs));
      store = synced;
      try {
        await synced.pull().timeout(const Duration(seconds: 6));
        synced.clearMissed(); // 화면을 만들기 전에 받았으니 다시 읽을 필요 없다
      } catch (_) {}
    }
  } catch (_) {
    store = MemoryStore();
  }
  // 토스 문항 모음 (없으면 말하기 단계는 예전 따라 말하기)
  final toeic = await loadToeicBank();
  runApp(
    ProviderScope(
      overrides: [storeProvider.overrideWithValue(store), toeicBankProvider.overrideWithValue(toeic)],
      child: const TodayeApp(),
    ),
  );
}
