import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import 'router.dart';
import 'study_controller.dart';

class TodayeApp extends ConsumerStatefulWidget {
  const TodayeApp({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  ConsumerState<TodayeApp> createState() => _TodayeAppState();
}

class _TodayeAppState extends ConsumerState<TodayeApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
    isOnboarded: () => ref.read(studyProvider).onboarded,
    isAllDone: () => ref.read(studyProvider).allDone,
  );

  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 다음 날 앱으로 돌아오면 오늘 기준으로 새로 고친다
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _checkDay();
        // 잠든 동안 타이머가 밀렸을 수 있으므로 다시 잡고, 휴대폰 설정에서 알림 권한을 바꿨을 수 있으니 다시 확인한다
        _scheduleMidnight();
        ref.read(studyProvider.notifier).syncReminder();
      },
    );
    _scheduleMidnight();
    // 탭 화면으로 이동할 때(학습 화면에서 돌아옴·탭 전환) 미뤄 둔 날짜 변경을 적용한다
    _router.routerDelegate.addListener(_onRoute);
    // 알림 문구를 오늘의 연속 학습일로 갱신
    Future.microtask(() {
      if (mounted) ref.read(studyProvider.notifier).syncReminder();
    });
  }

  bool get _onTab => tabPaths.contains(_router.routerDelegate.currentConfiguration.uri.path);

  void _checkDay() => refreshStudyDay(ref, fromHome: _onTab);

  void _onRoute() {
    if (!_onTab) return;
    // 내비게이션 처리 중에 상태를 바꾸지 않도록 한 프레임 뒤에
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _onTab) refreshStudyDay(ref, fromHome: true);
    });
  }

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
    WidgetsBinding.instance.removeObserver(this);
    _router.routerDelegate.removeListener(_onRoute);
    _midnight?.cancel();
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 테마: 설정이 system 이면 휴대폰의 밝기 설정을 따른다
    final theme = ref.watch(studyProvider.select((s) => s.settings.theme));
    final dark =
        theme == 'dark' ||
        (theme == 'system' && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    AppColors.use(dark ? AppPalette.dark : AppPalette.light);
    return MaterialApp.router(
      title: '오늘의 영어',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 색 토큰은 화면을 그릴 때 읽으므로, 테마가 바뀌면 화면 전체를 새로 만든다 (위치는 라우터가 기억)
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: KeyedSubtree(key: ValueKey(dark), child: child ?? const SizedBox.shrink()),
      ),
      routerConfig: _router,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
