import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fpdart/fpdart.dart';

import '../../api/domain/entities/enums.dart';
import '../../core/utils/logger.dart';
import '../firebase/messaging_service.dart';
import '../firebase/token_service.dart';
import '../messages/message_mapper.dart';
import '../models/notification_payload.dart';
import '../models/push_events.dart';
import '../models/push_settings.dart';
import '../notification/initial_notification.dart';
import '../notification/local_notification_service.dart';
import '../notification/notification_channel.dart';
import '../notification/notification_permission.dart';
import '../push_port.dart';

/// Composition root of the push side: Firebase, local notifications, the FCM
/// listeners, the token and the permission.
final class SignalPlusInstance implements PushPort {
  const SignalPlusInstance({
    required this.events,
    required this.notifications,
    required this.permissions,
    required this.tokens,
    required this.messaging,
    required this.initialNotification,
  });

  @override
  final PushEvents events;

  final LocalNotificationService notifications;

  final NotificationPermissionService permissions;

  final TokenService tokens;

  final MessagingService messaging;

  final InitialNotificationStore initialNotification;

  static Future<SignalPlusInstance> start({
    required final PushSettings config,
    final Option<FirebaseOptions> firebaseOptions = const None(),
    final Option<BackgroundMessageHandler> backgroundHandler = const None(),
  }) async {
    final KitLogger logger = config.kitLogger;

    await Firebase.initializeApp(options: firebaseOptions.toNullable());
    backgroundHandler.match(() {}, FirebaseMessaging.onBackgroundMessage);

    final FirebaseMessaging fcm = FirebaseMessaging.instance;
    await fcm.setForegroundNotificationPresentationOptions(
      alert: config.options.showForegroundNotification,
      badge: config.options.showForegroundNotification,
      sound: config.options.showForegroundNotification,
    );

    final PushEvents events = PushEvents();
    final InitialNotificationStore initialNotification = InitialNotificationStore();
    final LocalNotificationService notifications = LocalNotificationService(
      config: config,
      events: events,
      initialNotification: initialNotification,
      logger: logger,
    );
    await notifications.initialize();

    final MessagingService messaging = MessagingService(
      messaging: fcm,
      config: config,
      events: events,
      notifications: notifications,
      initialNotification: initialNotification,
      logger: logger,
    );
    await messaging.setupListeners();

    final TokenService tokens = TokenService(messaging: fcm, events: events, logger: logger)..listenForRefresh();
    final NotificationPermissionService permissions = NotificationPermissionService(
      messaging: fcm,
      events: events,
      logger: logger,
    );

    unawaited(tokens.refresh());
    if (config.options.requestPermissionOnStartup) unawaited(permissions.requestPermission());

    logger.info('Started');
    return SignalPlusInstance(
      events: events,
      notifications: notifications,
      permissions: permissions,
      tokens: tokens,
      messaging: messaging,
      initialNotification: initialNotification,
    );
  }

  /// Shows a data-only message from the background isolate.
  static Future<void> showBackgroundMessage(final RemoteMessage message, {required final PushSettings config}) async {
    if (!message.needsLocalDisplay(foreground: false)) return;

    final KitLogger logger = config.kitLogger;
    try {
      final LocalNotificationService notifications = LocalNotificationService(
        config: config,
        events: PushEvents(),
        initialNotification: InitialNotificationStore(),
        logger: logger,
      );
      await notifications.initialize(background: true);
      await notifications.show(MessageMapper.content(message, appName: config.appName));
    } on Object catch (error, stackTrace) {
      logger.error('Failed to show background message', error, stackTrace);
    }
  }

  @override
  Future<String> token() => tokens.getToken();

  @override
  Future<void> deleteToken() => tokens.deleteToken();

  @override
  Future<PushPermission> permission() => permissions.status();

  @override
  Future<PushPermission> requestPermission() => permissions.requestPermission();

  @override
  Future<void> registerChannels(final List<ChannelSpec> channels) => notifications.registerChannels(channels);

  @override
  Future<void> clearNotifications() => notifications.clearDisplayed();

  @override
  Option<NotificationPayload> takeInitialNotification() => initialNotification.take().alt(events.takePendingTap);

  @override
  Future<void> dispose() async {
    await messaging.dispose();
    await tokens.dispose();
    await events.close();
  }
}
