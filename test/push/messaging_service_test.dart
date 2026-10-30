import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/push/firebase/messaging_service.dart';
import 'package:signalplus/src/push/models/push_events.dart';
import 'package:signalplus/src/push/models/push_settings.dart';
import 'package:signalplus/src/push/notification/initial_notification.dart';
import 'package:signalplus/src/push/notification/local_notification_service.dart';

import '../support/push_fakes.dart';

const RemoteMessage notificationMessage = RemoteMessage(
  messageId: 'm1',
  notification: RemoteNotification(title: 'N', body: 'NB'),
  data: <String, dynamic>{'route': '/orders', 'NotifyId': 'ntf_01'},
);
const RemoteMessage dataOnlyMessage = RemoteMessage(
  messageId: 'm2',
  data: <String, dynamic>{'title': 'D', 'body': 'DB'},
);

void main() {
  late FakeMessaging fcm;
  late FakeLocalNotificationsPlugin plugin;
  late StreamController<RemoteMessage> onMessage;
  late StreamController<RemoteMessage> onOpened;
  late InitialNotificationStore initial;
  late List<NotificationPayload> taps;
  late List<RemoteMessage> foreground;
  late PushEvents events;
  late MessagingService service;

  MessagingService build({final PushSettings config = testConfig}) => MessagingService(
    messaging: fcm,
    config: config,
    events: events,
    notifications: LocalNotificationService(
      config: config,
      events: events,
      initialNotification: initial,
      logger: silentLogger,
      plugin: Some(plugin),
      loadImage: (final String url) async => const None(),
    ),
    initialNotification: initial,
    logger: silentLogger,
    onMessage: Some(onMessage.stream),
    onMessageOpenedApp: Some(onOpened.stream),
  );

  setUp(() {
    fcm = FakeMessaging();
    plugin = FakeLocalNotificationsPlugin();
    onMessage = StreamController<RemoteMessage>.broadcast();
    onOpened = StreamController<RemoteMessage>.broadcast();
    initial = InitialNotificationStore();
    taps = <NotificationPayload>[];
    foreground = <RemoteMessage>[];
    events = eventsWith(onTap: taps.add, onForeground: foreground.add);
    service = build();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await service.dispose();
  });

  group('foreground messages', () {
    test('Android shows notification messages locally', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await service.setupListeners();

      onMessage.add(notificationMessage);
      await pumpEventQueue();

      expect(foreground.single.messageId, 'm1');
      expect(plugin.shown.single.title, 'N');
    });

    test('iOS leaves notification messages to the system banner', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await service.setupListeners();

      onMessage.add(notificationMessage);
      await pumpEventQueue();

      expect(foreground, hasLength(1));
      expect(plugin.shown, isEmpty);
    });

    test('iOS shows data only messages locally', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await service.setupListeners();

      onMessage.add(dataOnlyMessage);
      await pumpEventQueue();

      expect(plugin.shown.single.title, 'D');
    });

    test('nothing is shown when foreground display is off', () async {
      service = build(
        config: const PushSettings(
          appName: 'A',
          locale: ServiceLocale.ar,
          options: PushConfig(showForegroundNotification: false),
        ),
      );
      await service.setupListeners();

      onMessage.add(dataOnlyMessage);
      await pumpEventQueue();

      expect(foreground, hasLength(1));
      expect(plugin.shown, isEmpty);
    });

    test('a failing display is logged, not thrown', () async {
      plugin.showError = StateError('boom');
      await service.setupListeners();

      onMessage.add(dataOnlyMessage);
      await pumpEventQueue();

      expect(plugin.shown, isEmpty);
    });
  });

  test('a tap while running reaches the callback and the taps stream with the NotifyId', () async {
    final List<NotificationPayload> streamed = <NotificationPayload>[];
    events.taps.listen(streamed.add);
    await service.setupListeners();

    onOpened.add(notificationMessage);
    await pumpEventQueue();

    expect(taps.single.title, 'N');
    expect(taps.single.body, 'NB');
    expect(taps.single.data['route'], '/orders');
    expect(streamed.single.notifyId, const Some('ntf_01'));
  });

  test('the launch message is stored, not tapped', () async {
    fcm.initialMessage = notificationMessage;

    await service.setupListeners();

    expect(taps, isEmpty);
    expect(initial.take().map((final NotificationPayload payload) => payload.title), const Some('N'));
  });

  test('if the launch message fails, no listener is registered', () async {
    fcm.initialMessageError = Exception('platform');

    await expectLater(service.setupListeners(), throwsException);

    expect(onMessage.hasListener, isFalse);
    expect(onOpened.hasListener, isFalse);
  });

  test('dispose cancels the listeners', () async {
    await service.setupListeners();
    expect(onMessage.hasListener, isTrue);

    await service.dispose();

    expect(onMessage.hasListener, isFalse);
    expect(onOpened.hasListener, isFalse);
  });
}
