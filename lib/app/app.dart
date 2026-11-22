import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';
import 'study_controller.dart';

class TodayeApp extends ConsumerStatefulWidget {
  const TodayeApp({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  ConsumerState<TodayeApp> createState() => _TodayeAppState();
}

class _TodayeAppState extends ConsumerState<TodayeApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
    isOnboarded: () => ref.read(studyProvider).onboarded,
  );

  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    // 다음 날 앱으로 돌아오면 오늘 기준으로 새로 고친다
    _lifecycle = AppLifecycleListener(onResume: _checkDay);
    _scheduleMidnight();
    // 알림 문구를 오늘의 연속 학습일로 갱신
    Future.microtask(() => ref.read(studyProvider.notifier).syncReminder());
  }

  void _checkDay() => ref.read(studyProvider.notifier).refreshIfNewDay();

  /// 앱을 켜 둔 채 학습일 경계(새벽 4시)를 넘기는 경우
  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = ref.read(clockProvider)();
    var next = DateTime(now.year, now.month, now.day, dayStartHour, 0, 5);
    if (!next.isAfter(now)) next = DateTime(now.year, now.month, now.day + 1, dayStartHour, 0, 5);
    _midnight = Timer(next.difference(now), () {
      _checkDay();
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '오늘의 영어',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
