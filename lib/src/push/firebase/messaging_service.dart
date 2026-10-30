import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/utils/logger.dart';
import '../messages/message_mapper.dart';
import '../models/push_events.dart';
import '../models/push_settings.dart';
import '../notification/initial_notification.dart';
import '../notification/local_notification_service.dart';

final class MessagingService {
  MessagingService({
    required this.messaging,
    required this.config,
    required this.events,
    required this.notifications,
    required this.initialNotification,
    required final KitLogger logger,
    final Option<Stream<RemoteMessage>> onMessage = const None(),
    final Option<Stream<RemoteMessage>> onMessageOpenedApp = const None(),
  }) : onMessage = onMessage.getOrElse(() => FirebaseMessaging.onMessage),
       onMessageOpenedApp = onMessageOpenedApp.getOrElse(() => FirebaseMessaging.onMessageOpenedApp),
       log = logger.tagged('MessagingService');

  final FirebaseMessaging messaging;

  final Stream<RemoteMessage> onMessage;

  final Stream<RemoteMessage> onMessageOpenedApp;

  final PushSettings config;

  final PushEvents events;

  final LocalNotificationService notifications;

  final InitialNotificationStore initialNotification;

  final KitLogger log;

  final List<StreamSubscription<RemoteMessage>> subscriptions = <StreamSubscription<RemoteMessage>>[];

  Future<void> setupListeners() async {
    Option.fromNullable(await messaging.getInitialMessage())
        .map((final RemoteMessage message) => MessageMapper.remote(message, appName: config.appName))
        .match(() {}, initialNotification.set);
    subscriptions.addAll(<StreamSubscription<RemoteMessage>>[
      onMessage.listen(onForegroundMessage),
      onMessageOpenedApp.listen(onOpenedApp),
    ]);
  }

  Future<void> dispose() async {
    await Future.wait(subscriptions.map((final StreamSubscription<RemoteMessage> item) => item.cancel()));
    subscriptions.clear();
  }

  void onForegroundMessage(final RemoteMessage message) {
    events.message(message);
    if (!shouldDisplayInForeground(message)) return;

    unawaited(
      notifications
          .show(MessageMapper.content(message, appName: config.appName))
          .catchError(
            (final Object error, final StackTrace stackTrace) =>
                log.error('Failed to show foreground message', error, stackTrace),
          ),
    );
  }

  bool shouldDisplayInForeground(final RemoteMessage message) =>
      config.options.showForegroundNotification && message.needsLocalDisplay(foreground: true);

  void onOpenedApp(final RemoteMessage message) => events.tap(MessageMapper.remote(message, appName: config.appName));
}
