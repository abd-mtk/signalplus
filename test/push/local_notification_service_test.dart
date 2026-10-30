import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/push/messages/message_mapper.dart';
import 'package:signalplus/src/push/models/push_settings.dart';
import 'package:signalplus/src/push/notification/initial_notification.dart';
import 'package:signalplus/src/push/notification/local_notification_service.dart';
import 'package:signalplus/src/push/notification/notification_channel.dart';
import 'package:signalplus/src/push/notification/notification_image.dart';

import '../support/push_fakes.dart';

final NotificationImage testImage = NotificationImage(Uint8List.fromList(<int>[1, 2, 3]), 'png');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLocalNotificationsPlugin plugin;
  late InitialNotificationStore initial;
  late List<NotificationPayload> taps;
  late List<String> requestedImages;

  LocalNotificationService service({
    final PushSettings config = testConfig,
    final Option<NotificationImage> image = const None(),
    final Option<Directory> attachmentDirectory = const None(),
  }) => LocalNotificationService(
    config: config,
    events: eventsWith(onTap: taps.add),
    initialNotification: initial,
    logger: silentLogger,
    plugin: Some(plugin),
    loadImage: (final String url) async {
      requestedImages.add(url);
      return image;
    },
    attachmentDirectory: attachmentDirectory,
  );

  setUp(() {
    plugin = FakeLocalNotificationsPlugin();
    initial = InitialNotificationStore();
    taps = <NotificationPayload>[];
    requestedImages = <String>[];
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('show', () {
    test('shows text with the data as JSON payload', () async {
      await service().show(
        const NotificationContent(id: 7, title: 'T', body: 'B', data: <String, dynamic>{'route': '/orders'}),
      );

      final ShownNotification shown = plugin.shown.single;
      expect(shown.id, 7);
      expect(shown.title, 'T');
      expect(jsonDecode(shown.payload!), <String, dynamic>{'route': '/orders'});
      expect(shown.details!.android!.styleInformation, isA<BigTextStyleInformation>());
      expect(shown.details!.android!.channelId, PushSettings.channelId);
    });

    test('Android uses a big picture when the image loads', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await service(
        image: Some(testImage),
      ).show(const NotificationContent(id: 1, title: 'T', body: 'B', imageUrl: Some('https://a.test/i.png')));

      final AndroidNotificationDetails android = plugin.shown.single.details!.android!;
      expect(requestedImages, <String>['https://a.test/i.png']);
      expect(android.styleInformation, isA<BigPictureStyleInformation>());
      expect(android.largeIcon, isA<ByteArrayAndroidBitmap>());
      expect(plugin.shown.single.details!.iOS!.attachments, isEmpty);
    });

    test('iOS attaches the image as a file', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final Directory dir = Directory.systemTemp.createTempSync('nk_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      await service(
        image: Some(testImage),
        attachmentDirectory: Some(dir),
      ).show(const NotificationContent(id: 1, title: 'T', body: 'B', imageUrl: Some('https://a.test/i.png')));

      final DarwinNotificationAttachment attachment = plugin.shown.single.details!.iOS!.attachments!.single;
      expect(attachment.filePath, startsWith(dir.path));
      expect(attachment.filePath, endsWith('.png'));
      expect(File(attachment.filePath).readAsBytesSync(), <int>[1, 2, 3]);
    });

    test('the notification is still shown when the image fails', () async {
      await service().show(
        const NotificationContent(id: 1, title: 'T', body: 'B', imageUrl: Some('https://a.test/i.png')),
      );

      expect(plugin.shown.single.details!.android!.styleInformation, isA<BigTextStyleInformation>());
    });

    test('images are not loaded when they are turned off', () async {
      const PushSettings config = PushSettings(
        appName: 'A',
        locale: ServiceLocale.ar,
        options: PushConfig(showNotificationImages: false),
      );

      await service(
        config: config,
        image: Some(testImage),
      ).show(const NotificationContent(id: 1, title: 'T', body: 'B', imageUrl: Some('https://a.test/i.png')));

      expect(requestedImages, isEmpty);
    });

    test('a registered category channel is used for its messages', () async {
      final LocalNotificationService notifications = service();
      await notifications.registerChannels(const <ChannelSpec>[
        ChannelSpec(id: 'Orders', name: 'الطلبات', description: 'تحديثات'),
      ]);

      await notifications.show(const NotificationContent(id: 1, title: 'T', body: 'B', channelId: Some('Orders')));
      await notifications.show(const NotificationContent(id: 2, title: 'T', body: 'B', channelId: Some('Unknown')));

      expect(plugin.shown.first.details!.android!.channelId, 'Orders');
      expect(plugin.shown.first.details!.android!.channelName, 'الطلبات');
      expect(plugin.shown.last.details!.android!.channelId, PushSettings.channelId);
    });

    test('plugin errors reach the caller', () async {
      plugin.showError = StateError('boom');

      expect(service().show(const NotificationContent(id: 1, title: 'T', body: 'B')), throwsStateError);
    });
  });

  group('group summary', () {
    const PushSettings grouped = PushSettings(
      appName: 'A',
      locale: ServiceLocale.ar,
      options: PushConfig(groupNotifications: true),
    );

    test('counts the grouped notifications actually displayed in the configured words', () async {
      plugin.active = const <ActiveNotification>[
        ActiveNotification(id: 1, groupKey: 'signalplus_default.group'),
        ActiveNotification(id: 2, groupKey: 'signalplus_default.group'),
        ActiveNotification(id: summaryNotificationId, groupKey: 'signalplus_default.group'),
        ActiveNotification(id: 3, groupKey: 'other'),
      ];

      await service(config: grouped).show(const NotificationContent(id: 2, title: 'T', body: 'B'));

      final ShownNotification summary = plugin.shown.last;
      expect(summary.id, summaryNotificationId);
      expect(summary.body, 'إشعارات جديدة: 2');
      expect(summary.details!.android!.setAsGroupSummary, isTrue);
    });

    test('there is no summary when nothing grouped is displayed', () async {
      await service(config: grouped).show(const NotificationContent(id: 2, title: 'T', body: 'B'));

      expect(plugin.shown.map((final ShownNotification item) => item.id), <int>[2]);
    });
  });

  group('initialize', () {
    test('uses the app notification icon when it ships one', () async {
      await service().initialize();

      expect(plugin.icons, <String>['@drawable/ic_notification']);
    });

    test('falls back to the launcher icon when the app has no notification icon', () async {
      plugin.invalidIcons = <String>{'@drawable/ic_notification'};

      await service().initialize();

      expect(plugin.icons, <String>['@drawable/ic_notification', '@mipmap/ic_launcher']);
    });

    test('other plugin errors are not swallowed', () async {
      plugin.invalidIcons = LocalNotificationService.icons.toSet();

      expect(service().initialize(), throwsA(isA<PlatformException>()));
    });

    test('keeps the launch notification instead of tapping it', () async {
      plugin.launchDetails = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: '{"route":"/orders"}',
        ),
      );

      await service().initialize();

      expect(taps, isEmpty);
      expect(initial.take().map((final NotificationPayload payload) => payload.data['route']), const Some('/orders'));
    });

    test('in the background a category message uses the channel Android already keeps', () async {
      plugin.android =
          FakeAndroidNotifications()
            ..channels.add(const AndroidNotificationChannel('orders', 'الطلبات', importance: Importance.high));
      final LocalNotificationService notifications = service();

      await notifications.initialize(background: true);
      await notifications.show(const NotificationContent(id: 1, title: 'T', body: 'B', channelId: Some('orders')));

      expect(plugin.shown.single.details!.android!.channelId, 'orders');
      expect(plugin.shown.single.details!.android!.importance, Importance.high);
    });

    test('a channel registered while running replaces the one read at start', () async {
      plugin.android = FakeAndroidNotifications()..channels.add(const AndroidNotificationChannel('orders', 'Orders'));
      final LocalNotificationService notifications = service();

      await notifications.initialize();
      await notifications.registerChannels(const <ChannelSpec>[
        ChannelSpec(id: 'orders', name: 'الطلبات', description: 'تحديثات'),
      ]);
      await notifications.show(const NotificationContent(id: 1, title: 'T', body: 'B', channelId: Some('orders')));

      expect(plugin.shown.single.details!.android!.channelName, 'الطلبات');
    });

    test('a failure reading the Android channels does not stop initialize', () async {
      plugin.android = FakeAndroidNotifications()..listError = PlatformException(code: 'boom');
      final LocalNotificationService notifications = service();

      await notifications.initialize(background: true);
      await notifications.show(const NotificationContent(id: 1, title: 'T', body: 'B', channelId: Some('orders')));

      expect(plugin.shown.single.details!.android!.channelId, PushSettings.channelId);
    });

    test('background mode neither reads launch details nor clears', () async {
      const PushSettings config = PushSettings(
        appName: 'A',
        locale: ServiceLocale.ar,
        options: PushConfig(clearNotificationsOnLaunch: true),
      );
      plugin
        ..active = const <ActiveNotification>[ActiveNotification(id: 1)]
        ..launchDetails = const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType: NotificationResponseType.selectedNotification,
          ),
        );

      await service(config: config).initialize(background: true);

      expect(plugin.cancelled, isEmpty);
      expect(initial.take(), const None());
    });

    test('taps while running reach the callback', () async {
      await service().initialize();

      plugin.onTap!(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'order:42',
        ),
      );

      expect(taps.single.rawPayload, const Some('order:42'));
    });
  });

  test('clearing cancels displayed notifications by id and tag only', () async {
    plugin.active = const <ActiveNotification>[
      ActiveNotification(id: 1),
      ActiveNotification(id: 0, tag: 'FCM-Notification:1'),
      ActiveNotification(),
    ];

    await service().clearDisplayed();

    expect(plugin.cancelled, <({int id, String? tag})>[(id: 1, tag: null), (id: 0, tag: 'FCM-Notification:1')]);
    expect(plugin.cancelledAll, isFalse);
    expect(plugin.cancelledPending, isFalse);
  });

  test('on iOS clearing also removes notifications delivered by FCM', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final List<String> calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNotificationService.native,
      (final MethodCall call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        LocalNotificationService.native,
        null,
      ),
    );

    await service().clearDisplayed();

    expect(calls, <String>['clearDelivered']);
  });

  test('on Android clearing does not call the iOS channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final List<String> calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      LocalNotificationService.native,
      (final MethodCall call) async {
        calls.add(call.method);
        return null;
      },
    );

    await service().clearDisplayed();

    expect(calls, isEmpty);
  });
}
