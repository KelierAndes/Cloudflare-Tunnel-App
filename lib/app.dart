import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'services/window_chrome.dart';
import 'theme/app_theme.dart';
import 'ui/shell.dart';

class TunnelApp extends StatefulWidget {
  const TunnelApp({super.key});

  @override
  State<TunnelApp> createState() => _TunnelAppState();
}

class _TunnelAppState extends State<TunnelApp> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await context.read<AppState>().shutdown();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final mode = switch (state.settings.themeMode) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        };
        final platformDark =
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
        final effectiveDark =
            mode == ThemeMode.dark ||
            (mode == ThemeMode.system && platformDark);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WindowChrome.setTitleBarDark(effectiveDark);
          // 手机状态栏/手势栏透明，图标颜色跟随主题。
          SystemChrome.setSystemUIOverlayStyle(
            SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: effectiveDark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: effectiveDark
                  ? Brightness.light
                  : Brightness.dark,
            ),
          );
        });
        return MaterialApp(
          title: 'Cloudflare Tunnel Manager',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: mode,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            dragDevices: {
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.trackpad,
            },
          ),
          home: const AppShell(),
        );
      },
    );
  }
}
