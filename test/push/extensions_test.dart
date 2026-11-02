import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/push/messages/extensions.dart';

void main() {
  group('RemoteMessageX', () {
    test('a message without a notification block is data only', () {
      expect(const RemoteMessage(data: <String, dynamic>{'title': 'T'}).isDataOnly, isTrue);
      expect(const RemoteMessage(notification: RemoteNotification()).isDataOnly, isFalse);
    });

    test('data title and body are read only when they are strings', () {
      const RemoteMessage message = RemoteMessage(data: <String, dynamic>{'title': 'T', 'body': 42});

      expect(message.dataTitle, const Some('T'));
      expect(message.dataBody, const None());
    });

    test('the android channel comes from the notification block', () {
      const RemoteMessage message = RemoteMessage(
        notification: RemoteNotification(android: AndroidNotification(channelId: 'Orders')),
      );

      expect(message.androidChannelId, const Some('Orders'));
      expect(const RemoteMessage().androidChannelId, const None());
    });
  });

  test('platform helpers', () {
    expect(TargetPlatform.android.isAndroid, isTrue);
    expect(TargetPlatform.iOS.isIOS, isTrue);
    expect(TargetPlatform.iOS.isApple, isTrue);
    expect(TargetPlatform.macOS.isApple, isTrue);
    expect(TargetPlatform.android.isApple, isFalse);
  });

  test('every authorization status maps to one of the four documented permissions', () {
    expect(AuthorizationStatus.authorized.pushPermission, PushPermission.granted);
    expect(AuthorizationStatus.provisional.pushPermission, PushPermission.provisional);
    expect(AuthorizationStatus.denied.pushPermission, PushPermission.denied);
    expect(AuthorizationStatus.notDetermined.pushPermission, PushPermission.notDetermined);
    expect(PushPermission.provisional.canDeliver, isTrue);
    expect(PushPermission.notDetermined.canDeliver, isFalse);
  });

  group('MapValuesX', () {
    final Map<String, dynamic> map = <String, dynamic>{
      'text': 'value',
      'empty': '',
      'number': 1,
      'nested': <String, String>{'a': 'b'},
    };

    test('textAt returns strings only', () {
      expect(map.textAt('text'), const Some('value'));
      expect(map.textAt('empty'), const Some(''));
      expect(map.textAt('number'), const None());
      expect(map.textAt('missing'), const None());
    });

    test('nonEmptyTextAt ignores empty strings', () {
      expect(map.nonEmptyTextAt('text'), const Some('value'));
      expect(map.nonEmptyTextAt('empty'), const None());
    });
  });

  test('only http and https urls with a host are web urls', () {
    expect('https://a.test/x.png'.isWebUrl, isTrue);
    expect('http://a.test'.isWebUrl, isTrue);
    expect('file:///etc/passwd'.isWebUrl, isFalse);
    expect('https://'.isWebUrl, isFalse);
    expect('not a url'.isWebUrl, isFalse);
  });

  test('group membership excludes the summary and anonymous notifications', () {
    expect(const ActiveNotification(id: 3, groupKey: 'g').isMemberOf('g'), isTrue);
    expect(const ActiveNotification(id: summaryNotificationId, groupKey: 'g').isMemberOf('g'), isFalse);
    expect(const ActiveNotification(id: 3, groupKey: 'other').isMemberOf('g'), isFalse);
  });

  test('masked never logs the full token', () {
    expect('abcdefghijklmnop'.masked, 'abcdefgh…');
    expect('short'.masked, '***');
  });
}
