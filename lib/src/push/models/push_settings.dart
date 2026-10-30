import 'package:fpdart/fpdart.dart';

import '../../api/domain/entities/enums.dart';
import '../../core/utils/json_reader.dart';
import '../../core/utils/logger.dart';
import 'push_config.dart';

/// [PushConfig] plus what the package works out by itself: the app's name and language.
final class PushSettings {
  const PushSettings({
    required this.appName,
    required this.locale,
    this.options = const PushConfig(),
    this.logger = const None(),
  });

  factory PushSettings.fromJson(final JsonMap json) => PushSettings(
    appName: JsonReader.string(json, 'AppName'),
    locale: JsonReader.optString(json, 'Locale').map(ServiceLocale.parse).getOrElse(() => ServiceLocale.ar),
    options: PushConfig(
      groupNotifications: JsonReader.boolean(json, 'Group'),
      showNotificationImages: JsonReader.boolean(json, 'Images'),
    ),
  );

  static const String channelId = 'signalplus_default';

  final String appName;

  final ServiceLocale locale;

  final PushConfig options;

  final Option<LogSink> logger;

  String get channelName => switch (locale) {
    ServiceLocale.ar => 'عامة',
    ServiceLocale.en => 'General',
  };

  String get channelDescription => switch (locale) {
    ServiceLocale.ar => 'إشعارات التطبيق العامة',
    ServiceLocale.en => 'General App Notifications',
  };

  String groupSummary(final int count) => switch (locale) {
    ServiceLocale.ar => 'إشعارات جديدة: $count',
    ServiceLocale.en => count == 1 ? '1 New Notification' : '$count New Notifications',
  };

  KitLogger get kitLogger => KitLogger.of(logger);

  PushSettings localized(final ServiceLocale value) =>
      PushSettings(appName: appName, locale: value, options: options, logger: logger);

  JsonMap toJson() => <String, dynamic>{
    'AppName': appName,
    'Locale': locale.wire,
    'Group': options.groupNotifications,
    'Images': options.showNotificationImages,
  };
}
