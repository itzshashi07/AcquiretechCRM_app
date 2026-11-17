import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';

/// Runs in a background isolate when a message arrives while the app is not
/// in the foreground. Notification messages are displayed by Android itself
/// on the `crm_alerts` channel, so there is nothing else to do here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

enum PushStatus {
  unknown,
  on,
  off,
  denied,

  /// The phone is ready but the workspace server has not been updated yet.
  serverPending,
  error,
}

/// Phone notifications through Firebase Cloud Messaging.
class PushCenter {
  PushCenter._();
  static final PushCenter instance = PushCenter._();

  static const channel = AndroidNotificationChannel(
    'crm_alerts',
    'Enquiries & reminders',
    description: 'New website enquiries, follow-up reminders and assignments.',
    importance: Importance.max,
  );
  static const _system = MethodChannel('crm/system');

  final _local = FlutterLocalNotificationsPlugin();

  /// A workspace path to open, such as `/leads?record=abc`, from a tapped notification.
  final ValueNotifier<String?> opened = ValueNotifier(null);

  /// Increments whenever a message arrives while the app is open.
  final ValueNotifier<int> received = ValueNotifier(0);

  final ValueNotifier<PushStatus> status = ValueNotifier(PushStatus.unknown);

  StreamSubscription<String>? _tokenRefresh;
  CrmApi? _api;

  Future<void> init() async {
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_crm')),
      onDidReceiveNotificationResponse: (response) => opened.value = response.payload ?? '/',
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => opened.value = m.data['url'] ?? '/');

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) opened.value = initial.data['url'] ?? '/';
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      opened.value = launch!.notificationResponse?.payload ?? '/';
    }
  }

  /// Android does not show notification messages while the app is open, so
  /// the app shows them itself with the same channel and look.
  Future<void> _showForeground(RemoteMessage message) async {
    received.value++;
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      id: message.messageId.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      payload: message.data['url'] ?? '/',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          color: const Color(0xFF176D55),
          tag: (message.data['tag'] as String?)?.isEmpty ?? true ? null : message.data['tag'] as String,
          styleInformation: BigTextStyleInformation(n.body ?? ''),
        ),
      ),
    );
  }

  /// Registers this phone for alerts. With [ask] it shows the Android
  /// permission dialog (only call that from a user action or first sign-in).
  Future<PushStatus> enable(CrmApi api, {bool ask = true}) async {
    _api = api;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = ask ? await messaging.requestPermission() : await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // Android reports "denied" both before asking and after a refusal.
        return status.value = ask ? PushStatus.denied : PushStatus.off;
      }
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return status.value = PushStatus.off;
      }
      // The CRM server sends through FCM HTTP v1 with `message.token`, which takes this
      // registration token (the newer register()/onRegistered API yields an installation ID).
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null) return status.value = PushStatus.error;
      await _register(token);
      // ignore: deprecated_member_use
      _tokenRefresh ??= messaging.onTokenRefresh.listen((t) => _register(t).catchError((_) => status.value));
      return status.value;
    } catch (e) {
      debugPrint('push enable failed: $e');
      return status.value = PushStatus.error;
    }
  }

  Future<PushStatus> _register(String token) async {
    final api = _api;
    if (api == null) return status.value;
    try {
      await api.post('/push/app', {'token': token});
      return status.value = PushStatus.on;
    } on ApiException catch (e) {
      return status.value = e.status == 404 ? PushStatus.serverPending : PushStatus.error;
    }
  }

  /// Sends a test notification to every device of the signed-in user.
  Future<int> sendTest(CrmApi api) async {
    final data = await api.post('/push/test');
    return (data is Map ? data['delivered'] as num? : null)?.toInt() ?? 0;
  }

  /// A new account on this phone must get its own token.
  Future<void> signOut() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    _api = null;
    status.value = PushStatus.unknown;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> openSystemSettings() async {
    try {
      await _system.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }
}
