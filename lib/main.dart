import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'features/login.dart';
import 'features/shell.dart';
import 'ui/brand_logo.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(lightBars);
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  final state = AppState();
  runApp(AppScope(state: state, child: const CrmApp()));
  // Everything below runs after the first frame is on screen.
  unawaited(PushCenter.instance.init());
  unawaited(state.boot());
}

class CrmApp extends StatelessWidget {
  const CrmApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Keep text crisp but never let huge system font sizes break layouts.
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: media.textScaler.clamp(minScaleFactor: .9, maxScaleFactor: 1.25)),
            child: child!,
          );
        },
        home: const _Gate(),
      );
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget child = app.booting
        ? const _Splash()
        : app.user == null
            ? const LoginScreen()
            : Shell(key: ValueKey('shell-${app.user!.id}-${app.user!.role}'));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      child: child,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const AnnotatedRegion<SystemUiOverlayStyle>(
        value: darkBars,
        child: ColoredBox(
          color: Brand.ink,
          child: Center(child: AqMark(size: 72)),
        ),
      );
}
