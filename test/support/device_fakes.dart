import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/core/storage/key_value_store.dart';
import 'package:signalplus/src/device/device_snapshot.dart';
import 'package:signalplus/src/push/models/push_events.dart';
import 'package:signalplus/src/push/notification/notification_channel.dart';
import 'package:signalplus/src/push/push_port.dart';

final class MemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<Option<String>> read(final String key) async => Option.fromNullable(values[key]);

  @override
  Future<void> write(final String key, final String value) async => values[key] = value;
}

final class FixedDevice implements DeviceSnapshotReader {
  const FixedDevice();

  static const DeviceSnapshot snapshot = DeviceSnapshot(
    platform: DevicePlatform.android,
    appVersion: '1.1.1',
    buildNumber: '7',
    timeZone: 'Asia/Baghdad',
    appName: 'Shop',
    osVersion: Some('Android 15'),
    deviceModel: Some('Pixel 9'),
  );

  @override
  Future<DeviceSnapshot> read() async => snapshot;
}

final class FakePushPort implements PushPort {
  @override
  final PushEvents events = PushEvents();

  String fcmToken = 't1';
  Option<Object> tokenError = const None();
  PushPermission status = PushPermission.granted;
  Option<NotificationPayload> launch = const None();
  final List<ChannelSpec> channels = <ChannelSpec>[];
  bool cleared = false;
  bool disposed = false;

  void rotateToken(final String value) {
    fcmToken = value;
    events.token(value);
  }

  void changePermission(final PushPermission value) {
    status = value;
    events.permission(value);
  }

  @override
  Future<String> token() async => tokenError.match(() => fcmToken, (final Object error) => throw error);

  @override
  Future<void> deleteToken() async => events.forgetToken();

  @override
  Future<PushPermission> permission() async => status;

  @override
  Future<PushPermission> requestPermission() async => status;

  @override
  Future<void> registerChannels(final List<ChannelSpec> value) async => channels.addAll(value);

  final List<String> deletedChannels = <String>[];

  @override
  Future<void> deleteChannels(final List<String> ids) async => deletedChannels.addAll(ids);

  @override
  Future<void> clearNotifications() async => cleared = true;

  @override
  Option<NotificationPayload> takeInitialNotification() {
    final Option<NotificationPayload> taken = launch.alt(events.takePendingTap);
    launch = const None();
    return taken;
  }

  @override
  Future<void> dispose() async => disposed = true;
}
