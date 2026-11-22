import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:todaye/core/theme/tokens.dart';

/// 모든 테스트 전에 색 팔레트를 밝은 종이로 되돌린다 (AppColors 는 전역이라 테스트끼리 새지 않게).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => AppColors.use(AppPalette.light));
  await testMain();
}
