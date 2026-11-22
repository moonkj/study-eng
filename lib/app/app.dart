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

  @override
  void dispose() {
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
