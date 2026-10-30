import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/utils/logger.dart';
import '../messages/message_mapper.dart';
import '../models/notification_payload.dart';
import '../models/push_events.dart';
import '../models/push_settings.dart';
import 'initial_notification.dart';
import 'notification_channel.dart';
import 'notification_details_factory.dart';
import 'notification_image.dart';

final class LocalNotificationService {
  LocalNotificationService({
    required this.config,
    required this.events,
    required this.initialNotification,
    required final KitLogger logger,
    final Option<FlutterLocalNotificationsPlugin> plugin = const None(),
    final NotificationImageLoader loadImage = NotificationImages.download,
    this.attachmentDirectory = const None(),
  }) : plugin = plugin.getOrElse(FlutterLocalNotificationsPlugin.new),
       loadImage = config.options.showNotificationImages ? loadImage : NotificationImages.none,
       details = NotificationDetailsFactory(config),
       log = logger.tagged('LocalNotificationService');

  final FlutterLocalNotificationsPlugin plugin;

  final PushSettings config;

  final PushEvents events;

  final InitialNotificationStore initialNotification;

  final NotificationImageLoader loadImage;

  final Option<Directory> attachmentDirectory;

  final NotificationDetailsFactory details;

  final KitLogger log;

  final Map<String, ChannelSpec> categoryChannels = <String, ChannelSpec>{};

  static const MethodChannel native = MethodChannel('signalplus');

  /// The app's own notification icon when it ships one, otherwise its launcher icon.
  static const List<String> icons = <String>['@drawable/ic_notification', '@mipmap/ic_launcher'];

  Future<void> initialize({final bool background = false}) async {
    await initializeWith(icons);
    await AndroidChannels.create(plugin, <ChannelSpec>[details.defaultChannel]);
    await loadExistingChannels();
    if (background) return;

    if (config.options.clearNotificationsOnLaunch) await clearDisplayed();

    final Option<NotificationAppLaunchDetails> launch = Option.fromNullable(
      await plugin.getNotificationAppLaunchDetails(),
    );
    launch
        .filter((final NotificationAppLaunchDetails value) => value.didNotificationLaunchApp)
        .flatMap((final NotificationAppLaunchDetails value) => Option.fromNullable(value.notificationResponse))
        .map((final NotificationResponse response) => payloadOf(response))
        .match(() {}, initialNotification.set);
    log.info('Initialized');
  }

  Future<void> initializeWith(final List<String> candidates) async {
    try {
      await plugin.initialize(
        settings: InitializationSettings(
          android: AndroidInitializationSettings(candidates.first),
          iOS: const DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: onTap,
      );
    } on PlatformException catch (error) {
      if (error.code != 'invalid_icon' || candidates.length == 1) rethrow;
      await initializeWith(candidates.sublist(1));
    }
  }

  Future<void> loadExistingChannels() async {
    try {
      for (final ChannelSpec channel in await AndroidChannels.existing(plugin)) {
        categoryChannels.putIfAbsent(channel.id, () => channel);
      }
    } on Object catch (error, stackTrace) {
      log.error('Failed to read the Android channels', error, stackTrace);
    }
  }

  /// Deletes the channels among [ids] that Android has, so no channel is deleted that never existed.
  Future<void> deleteChannels(final List<String> ids) async {
    final List<String> existing = ids.where(categoryChannels.containsKey).toList();
    await AndroidChannels.delete(plugin, existing);
    existing.forEach(categoryChannels.remove);
  }

  Future<void> registerChannels(final List<ChannelSpec> channels) async {
    await AndroidChannels.create(plugin, channels);
    for (final ChannelSpec channel in channels) {
      categoryChannels[channel.id] = channel;
    }
  }

  Future<void> show(final NotificationContent content) async {
    final Option<NotificationImage> image = await content.imageUrl.match(
      () async => const None(),
      (final String url) => loadImage(url),
    );
    final Option<String> attachmentPath =
        defaultTargetPlatform.isIOS
            ? await image.match(
              () async => const None(),
              (final NotificationImage value) => attachmentFor(content.id, value),
            )
            : const None();

    await plugin.show(
      id: content.id,
      title: content.title,
      body: content.body,
      notificationDetails: details.message(
        title: content.title,
        body: content.body,
        image: image,
        attachmentPath: attachmentPath,
        channel: content.channelId.flatMap((final String id) => Option.fromNullable(categoryChannels[id])),
      ),
      payload: jsonEncode(content.data),
    );
    if (config.options.groupNotifications) await updateGroupSummary();
  }

  Future<Option<String>> attachmentFor(final int id, final NotificationImage image) async {
    try {
      return some(
        await NotificationImages.writeAttachment(
          image,
          id: id,
          directory: attachmentDirectory.getOrElse(() => Directory.systemTemp),
        ),
      );
    } on FileSystemException catch (error, stackTrace) {
      log.error('Failed to write image attachment', error, stackTrace);
      return const None();
    }
  }

  Future<void> updateGroupSummary() async {
    final List<ActiveNotification> active = await plugin.getActiveNotifications();
    final int count = active.where((final ActiveNotification item) => item.isMemberOf(details.groupKey)).length;
    if (count == 0) return;

    await plugin.show(
      id: summaryNotificationId,
      title: config.appName,
      body: config.groupSummary(count),
      notificationDetails: details.summary(count),
      payload: jsonEncode(<String, bool>{'isSummary': true}),
    );
  }

  Future<void> clearDisplayed() async {
    if (defaultTargetPlatform.isIOS) return native.invokeMethod<void>('clearDelivered');
    final List<ActiveNotification> active = await plugin.getActiveNotifications();
    await Future.wait(<Future<void>>[
      for (final ActiveNotification item in active)
        if (item.id case final int id) plugin.cancel(id: id, tag: item.tag),
    ]);
  }

  NotificationPayload payloadOf(final NotificationResponse response) =>
      MessageMapper.local(Option.fromNullable(response.payload), defaultTitle: config.appName);

  void onTap(final NotificationResponse response) => events.tap(payloadOf(response));
}
