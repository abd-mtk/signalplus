import 'package:fpdart/fpdart.dart';

import '../api/domain/entities/enums.dart';
import 'models/notification_payload.dart';
import 'models/push_events.dart';
import 'notification/notification_channel.dart';

abstract class PushPort {
  PushEvents get events;

  Future<String> token();

  Future<void> deleteToken();

  Future<PushPermission> permission();

  Future<PushPermission> requestPermission();

  Future<void> registerChannels(final List<ChannelSpec> channels);

  Future<void> deleteChannels(final List<String> ids);

  Future<void> clearNotifications();

  Option<NotificationPayload> takeInitialNotification();

  Future<void> dispose();
}
