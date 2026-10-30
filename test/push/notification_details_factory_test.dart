import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/push/models/push_settings.dart';
import 'package:signalplus/src/push/notification/notification_channel.dart';
import 'package:signalplus/src/push/notification/notification_details_factory.dart';
import 'package:signalplus/src/push/notification/notification_image.dart';

import '../support/push_fakes.dart';

void main() {
  const NotificationDetailsFactory factory = NotificationDetailsFactory(testConfig);

  test('without grouping there is no group key', () {
    expect(factory.message(title: 'T', body: 'B').android!.groupKey, isNull);
  });

  test('message and summary share the group key when grouping is on', () {
    const NotificationDetailsFactory grouped = NotificationDetailsFactory(
      PushSettings(appName: 'A', locale: ServiceLocale.ar, options: PushConfig(groupNotifications: true)),
    );

    expect(grouped.groupKey, 'signalplus_default.group');
    expect(grouped.message(title: 'T', body: 'B').android!.groupKey, 'signalplus_default.group');
    expect(grouped.summary(3).android!.groupKey, 'signalplus_default.group');
  });

  test('an image gives a big picture and an attachment', () {
    final NotificationDetails details = factory.message(
      title: 'T',
      body: 'B',
      image: Some(NotificationImage(Uint8List(1), 'jpg')),
      attachmentPath: const Some('/tmp/x.jpg'),
    );

    expect(details.android!.styleInformation, isA<BigPictureStyleInformation>());
    expect(details.iOS!.attachments!.single.filePath, '/tmp/x.jpg');
  });

  test('a category channel sets the android channel and the iOS thread', () {
    final NotificationDetails details = factory.message(
      title: 'T',
      body: 'B',
      channel: const Some(ChannelSpec(id: 'Orders', name: 'Orders', description: '', importance: Importance.high)),
    );

    expect(details.android!.channelId, 'Orders');
    expect(details.android!.importance, Importance.high);
    expect(details.iOS!.threadIdentifier, 'Orders');
  });

  test('lanes map to channel importance', () {
    expect(ChannelSpec.importanceFor(Lane.critical), Importance.max);
    expect(ChannelSpec.importanceFor(Lane.transactional), Importance.high);
    expect(ChannelSpec.importanceFor(Lane.bulk), Importance.defaultImportance);
  });
}
