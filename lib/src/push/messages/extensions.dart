import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fpdart/fpdart.dart';

import '../../api/domain/entities/enums.dart';
import '../../core/utils/option_extensions.dart';
import 'message_keys.dart';

const int summaryNotificationId = 0;

extension RemoteMessageX on RemoteMessage {
  Option<RemoteNotification> get notificationBlock => Option.fromNullable(notification);

  bool get isDataOnly => notificationBlock.isNone();

  bool needsLocalDisplay({required final bool foreground}) =>
      isDataOnly || (foreground && defaultTargetPlatform.isAndroid);

  Option<String> get dataTitle => data.nonEmptyTextAt(MessageKeys.title);

  Option<String> get dataBody => data.nonEmptyTextAt(MessageKeys.body);

  Option<String> get imageUrl =>
      <Option<String>>[
            notificationBlock.flatMap(
              (final RemoteNotification block) => Option.fromNullable(
                block.android,
              ).flatMap((final AndroidNotification android) => Option.fromNullable(android.imageUrl)),
            ),
            notificationBlock.flatMap(
              (final RemoteNotification block) => Option.fromNullable(
                block.apple,
              ).flatMap((final AppleNotification apple) => Option.fromNullable(apple.imageUrl)),
            ),
            data.textAt(MessageKeys.image),
          ]
          .map((final Option<String> url) => url.filter((final String value) => value.isWebUrl))
          .firstWhere((final Option<String> url) => url.isSome(), orElse: () => const None());

  Option<String> get androidChannelId => notificationBlock.flatMap(
    (final RemoteNotification block) => Option.fromNullable(
      block.android,
    ).flatMap((final AndroidNotification android) => Option.fromNullable(android.channelId)),
  );
}

extension TargetPlatformX on TargetPlatform {
  bool get isAndroid => this == TargetPlatform.android;

  bool get isIOS => this == TargetPlatform.iOS;

  bool get isApple => this == TargetPlatform.iOS || this == TargetPlatform.macOS;
}

extension AuthorizationStatusX on AuthorizationStatus {
  PushPermission get pushPermission => switch (this) {
    AuthorizationStatus.authorized => PushPermission.granted,
    AuthorizationStatus.provisional => PushPermission.provisional,
    AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notDetermined,
  };
}

extension MapValuesX on Map<dynamic, dynamic> {
  Option<String> textAt(final Object key) => switch (this[key]) {
    final String text => some(text),
    _ => const None(),
  };

  Option<String> nonEmptyTextAt(final Object key) => textAt(key).filter((final String text) => text.isNotEmpty);
}

extension StringX on String {
  bool get isWebUrl => Option.fromNullable(
    Uri.tryParse(this),
  ).exists((final Uri uri) => uri.host.isNotEmpty && (uri.isScheme('http') || uri.isScheme('https')));

  String get masked => length > 8 ? '${substring(0, 8)}…' : '***';
}

extension ActiveNotificationX on ActiveNotification {
  bool isMemberOf(final String group) =>
      groupKey == group && !Option.fromNullable(id).exists((final int value) => value == summaryNotificationId);
}
