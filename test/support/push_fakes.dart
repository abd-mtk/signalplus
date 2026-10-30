import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/core/utils/logger.dart';
import 'package:signalplus/src/push/models/push_events.dart';
import 'package:signalplus/src/push/models/push_settings.dart';

const PushSettings testConfig = PushSettings(appName: 'Test App', locale: ServiceLocale.ar);

const KitLogger silentLogger = KitLogger(sink: KitLogger.silentSink);

PushEvents eventsWith({
  final void Function(NotificationPayload payload) onTap = ignore,
  final void Function(String token) onToken = ignore,
  final void Function(RemoteMessage message) onForeground = ignore,
  final void Function(PushPermission permission) onPermission = ignore,
}) {
  final PushEvents events = PushEvents();
  events.taps.listen(onTap);
  events.tokens.listen(onToken);
  events.messages.listen(onForeground);
  events.permissions.listen(onPermission);
  return events;
}

void ignore(final Object? value) {}

class FakeMessaging implements FirebaseMessaging {
  final registeredController = StreamController<String>.broadcast();
  String? token = 'token-1234567890';
  List<String?> apnsTokens = ['apns'];
  int apnsCalls = 0;
  int registerCalls = 0;
  Object? registerError;

  @override
  Stream<String> get onRegistered => registeredController.stream;

  @override
  Future<String?> getAPNSToken() async {
    final index = apnsCalls < apnsTokens.length ? apnsCalls : apnsTokens.length - 1;
    apnsCalls++;
    return apnsTokens[index];
  }

  @override
  Future<void> register({final String? serviceWorkerScriptPath, final String? vapidKey}) async {
    registerCalls++;
    if (registerError != null) throw registerError!;
    if (token case final String value) registeredController.add(value);
  }

  @override
  Future<void> unregister() async => token = null;

  RemoteMessage? initialMessage;
  Object? initialMessageError;

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    if (initialMessageError != null) throw initialMessageError!;
    return initialMessage;
  }

  Completer<AuthorizationStatus> permission = Completer();
  int permissionRequests = 0;

  @override
  Future<NotificationSettings> requestPermission({
    final bool alert = true,
    final bool announcement = false,
    final bool badge = true,
    final bool carPlay = false,
    final bool criticalAlert = false,
    final bool provisional = false,
    final bool sound = true,
    final bool providesAppNotificationSettings = false,
  }) async {
    permissionRequests++;
    return settingsWith(await permission.future);
  }

  AuthorizationStatus status = AuthorizationStatus.authorized;

  @override
  Future<NotificationSettings> getNotificationSettings() async => settingsWith(status);

  @override
  dynamic noSuchMethod(final Invocation invocation) => super.noSuchMethod(invocation);
}

typedef ShownNotification = ({int id, String? title, String? body, NotificationDetails? details, String? payload});

class FakeLocalNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  final shown = <ShownNotification>[];
  final cancelled = <({int id, String? tag})>[];
  List<ActiveNotification> active = [];
  NotificationAppLaunchDetails? launchDetails;
  DidReceiveNotificationResponseCallback? onTap;
  Object? showError;
  bool cancelledAll = false;
  bool cancelledPending = false;
  Set<String> invalidIcons = {};
  final icons = <String>[];

  @override
  Future<bool?> initialize({
    required final InitializationSettings settings,
    final DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    final DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async {
    final String icon = settings.android!.defaultIcon;
    icons.add(icon);
    if (invalidIcons.contains(icon)) throw PlatformException(code: 'invalid_icon');
    onTap = onDidReceiveNotificationResponse;
    return true;
  }

  FakeAndroidNotifications? android;

  @override
  T? resolvePlatformSpecificImplementation<T extends FlutterLocalNotificationsPlatform>() =>
      android is T ? android as T : null;

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async => launchDetails;

  @override
  Future<void> show({
    required final int id,
    final String? title,
    final String? body,
    final NotificationDetails? notificationDetails,
    final String? payload,
  }) async {
    if (showError != null) throw showError!;
    shown.add((id: id, title: title, body: body, details: notificationDetails, payload: payload));
  }

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => active;

  @override
  Future<void> cancel({required final int id, final String? tag}) async => cancelled.add((id: id, tag: tag));

  @override
  Future<void> cancelAll() async => cancelledAll = true;

  @override
  Future<void> cancelAllPendingNotifications() async => cancelledPending = true;

  @override
  dynamic noSuchMethod(final Invocation invocation) => super.noSuchMethod(invocation);
}

NotificationSettings settingsWith(final AuthorizationStatus status) {
  return NotificationSettings(
    alert: AppleNotificationSetting.enabled,
    announcement: AppleNotificationSetting.disabled,
    authorizationStatus: status,
    badge: AppleNotificationSetting.enabled,
    carPlay: AppleNotificationSetting.disabled,
    lockScreen: AppleNotificationSetting.enabled,
    notificationCenter: AppleNotificationSetting.enabled,
    showPreviews: AppleShowPreviewSetting.always,
    timeSensitive: AppleNotificationSetting.disabled,
    criticalAlert: AppleNotificationSetting.disabled,
    sound: AppleNotificationSetting.enabled,
    providesAppNotificationSettings: AppleNotificationSetting.disabled,
  );
}

class FakeAndroidNotifications implements AndroidFlutterLocalNotificationsPlugin {
  final channels = <AndroidNotificationChannel>[];
  Object? listError;

  @override
  Future<void> createNotificationChannel(final AndroidNotificationChannel notificationChannel) async {
    channels
      ..removeWhere((final AndroidNotificationChannel item) => item.id == notificationChannel.id)
      ..add(notificationChannel);
  }

  @override
  Future<List<AndroidNotificationChannel>?> getNotificationChannels() async {
    if (listError != null) throw listError!;
    return channels;
  }

  @override
  dynamic noSuchMethod(final Invocation invocation) => super.noSuchMethod(invocation);
}
