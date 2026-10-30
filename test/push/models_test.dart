import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/push/models/push_settings.dart';

void main() {
  group('PushConfig', () {
    test('optional values have defaults', () {
      const PushConfig config = PushConfig();

      expect(config.requestPermissionOnStartup, isTrue);
      expect(config.showForegroundNotification, isTrue);
      expect(config.showNotificationImages, isTrue);
      expect(config.clearNotificationsOnLaunch, isFalse);
      expect(config.groupNotifications, isFalse);
    });
  });

  group('PushSettings', () {
    test('the channel and the group summary speak the app language', () {
      const PushSettings arabic = PushSettings(appName: 'A', locale: ServiceLocale.ar);
      final PushSettings english = arabic.localized(ServiceLocale.en);

      expect(arabic.channelName, 'الإشعارات العامة');
      expect(arabic.groupSummary(3), 'إشعارات جديدة: 3');
      expect(english.channelName, 'General Notifications');
      expect(english.groupSummary(1), '1 New Notification');
      expect(english.groupSummary(2), '2 New Notifications');
    });

    test('without a locale the device language is used', () {
      final TestPlatformDispatcher dispatcher = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
      addTearDown(dispatcher.clearLocaleTestValue);

      dispatcher.localeTestValue = const Locale('ar', 'IQ');
      expect(const SignalPlusConfig(appId: 'sdk').language, ServiceLocale.ar);

      dispatcher.localeTestValue = const Locale('fr');
      expect(const SignalPlusConfig(appId: 'sdk').language, ServiceLocale.en);

      expect(const SignalPlusConfig(appId: 'sdk', locale: Some(ServiceLocale.ar)).language, ServiceLocale.ar);
    });

    test('a custom log sink receives the log lines', () {
      final List<String> lines = <String>[];
      final SignalPlusConfig config = SignalPlusConfig(
        appId: 'sdk',
        locale: const Some(ServiceLocale.ar),
        logger: Some((final String tag, final String message) => lines.add('$tag:$message')),
      );

      config.settings(appName: 'A').kitLogger.info('hello');

      expect(lines, <String>['SignalPlus:hello']);
    });
  });

  group('NotificationPayload', () {
    test('fromMap extracts title, body and data', () {
      final NotificationPayload payload = NotificationPayload.fromMap(<String, dynamic>{
        'title': 'Test Title',
        'body': 'Test Body',
        'key1': 'value1',
        'key2': 123,
      });

      expect(payload.title, 'Test Title');
      expect(payload.body, 'Test Body');
      expect(payload.data['key2'], 123);
      expect(payload.rawPayload, const None());
    });

    test('the default title is used when there is none', () {
      final NotificationPayload payload = NotificationPayload.fromMap(<String, dynamic>{
        'body': 'Body only',
      }, defaultTitle: 'Fallback App');

      expect(payload.title, 'Fallback App');
      expect(payload.body, 'Body only');
    });

    test('a nested notification map is read', () {
      final NotificationPayload payload = NotificationPayload.fromMap(<String, dynamic>{
        'notification': <String, String>{'title': 'Nested', 'body': 'Nested body'},
      });

      expect(payload.title, 'Nested');
      expect(payload.body, 'Nested body');
    });

    test('non string titles and non map notifications are ignored', () {
      expect(NotificationPayload.fromMap(<String, dynamic>{'title': 42}, defaultTitle: 'F').title, 'F');
      expect(NotificationPayload.fromMap(<String, dynamic>{'notification': 'oops'}, defaultTitle: 'F').body, '');
    });

    test('an empty body falls back to the default body', () {
      expect(NotificationPayload.fromMap(<String, dynamic>{'body': ''}, defaultBody: 'From FCM').body, 'From FCM');
    });

    test('the service NotifyId and Category are read from data', () {
      final NotificationPayload payload = NotificationPayload.fromMap(<String, dynamic>{
        'NotifyId': 'ntf_01',
        'Category': 'Orders',
      });

      expect(payload.notifyId, const Some('ntf_01'));
      expect(payload.category, const Some('Orders'));
      expect(NotificationPayload.fromMap(<String, dynamic>{'NotifyId': ''}).notifyId, const None());
    });
  });
}
