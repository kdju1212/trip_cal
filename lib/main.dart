import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'controller.dart';
import 'storage.dart';
import 'screens/home.dart';
import 'screens/trip_detail.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final app = AppController(await Storage.open());
    await app.load();
    runApp(TripApp(app));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('기기 저장소를 열지 못했어요. 저장 공간을 확인하고 다시 시도해 주세요.'),
                  TextButton(onPressed: main, child: const Text('다시 시도')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TripApp extends StatefulWidget {
  const TripApp(this.app, {super.key});
  final AppController app;
  @override
  State<TripApp> createState() => _TripAppState();
}

class _TripAppState extends State<TripApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.notifications.onOpen = openTrip;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = await widget.app.notifications.initialTrip();
      if (id != null && mounted) {
        openTrip(id);
      }
    });
  }

  void openTrip(int id) {
    navigator.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => TripDetail(widget.app, id)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.app.changed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.notifications.onOpen = null;
    super.dispose();
  }

  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2868E8),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF5F7FC)
          : const Color(0xFF10151F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app,
    builder: (context, _) => MaterialApp(
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      title: '여행 준비 도우미',
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: widget.app.themeMode,
      home: Home(widget.app),
    ),
  );
}
