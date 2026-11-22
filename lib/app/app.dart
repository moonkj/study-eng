import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class TodayeApp extends StatefulWidget {
  const TodayeApp({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  State<TodayeApp> createState() => _TodayeAppState();
}

class _TodayeAppState extends State<TodayeApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

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
