import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fpdart/fpdart.dart';

import '../../api/domain/entities/enums.dart';
import '../models/push_settings.dart';

final class ChannelSpec {
  const ChannelSpec({
    required this.id,
    required this.name,
    required this.description,
    this.importance = Importance.max,
  });

  factory ChannelSpec.fromSettings(final PushSettings settings) =>
      ChannelSpec(id: PushSettings.channelId, name: settings.channelName, description: settings.channelDescription);

  final String id;

  final String name;

  final String description;

  final Importance importance;

  static Importance importanceFor(final Lane lane) => switch (lane) {
    Lane.critical => Importance.max,
    Lane.transactional => Importance.high,
    Lane.bulk => Importance.defaultImportance,
  };
}

abstract final class AndroidChannels {
  static Option<AndroidFlutterLocalNotificationsPlugin> of(final FlutterLocalNotificationsPlugin plugin) =>
      Option.fromNullable(plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>());

  /// The channels Android already keeps for the app; they outlive the process that created them.
  static Future<List<ChannelSpec>> existing(final FlutterLocalNotificationsPlugin plugin) => of(plugin).match(
    () async => const <ChannelSpec>[],
    (final AndroidFlutterLocalNotificationsPlugin platform) async => <ChannelSpec>[
      for (final AndroidNotificationChannel channel
          in await platform.getNotificationChannels() ?? const <AndroidNotificationChannel>[])
        ChannelSpec(
          id: channel.id,
          name: channel.name,
          description: channel.description ?? '',
          importance: channel.importance,
        ),
    ],
  );

  static Future<void> delete(final FlutterLocalNotificationsPlugin plugin, final List<String> ids) =>
      of(plugin).match(() async {}, (final AndroidFlutterLocalNotificationsPlugin platform) async {
        for (final String id in ids) {
          await platform.deleteNotificationChannel(channelId: id);
        }
      });

  static Future<void> create(final FlutterLocalNotificationsPlugin plugin, final List<ChannelSpec> channels) async {
    await of(plugin).match(() async {}, (final AndroidFlutterLocalNotificationsPlugin platform) async {
      for (final ChannelSpec channel in channels) {
        await platform.createNotificationChannel(
          AndroidNotificationChannel(
            channel.id,
            channel.name,
            description: channel.description,
            importance: channel.importance,
            enableLights: true,
            enableVibration: true,
            showBadge: true,
          ),
        );
      }
    });
  }
}
