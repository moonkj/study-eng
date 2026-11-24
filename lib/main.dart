import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'data/store.dart';
import 'data/toeic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 저장소를 열지 못해도(파일 손상 등) 앱은 켜지게: 이번 실행은 메모리에만 저장한다
  AppStore store;
  try {
    store = PrefsStore(await SharedPreferences.getInstance());
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
