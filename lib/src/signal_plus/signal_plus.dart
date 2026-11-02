import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../api/domain/entities/catalog.dart';
import '../api/domain/entities/device_auth.dart';
import '../api/domain/entities/enums.dart';
import '../api/domain/entities/installation.dart';
import '../api/domain/entities/preferences.dart';
import '../core/kits/data_kit.dart';
import '../push/models/notification_payload.dart';
import '../push/push_port.dart';
import 'background_entry.dart';
import 'category_switch.dart';
import 'signal_plus_config.dart';
import 'signal_plus_runtime.dart';
import 'signal_plus_state.dart';

abstract final class SignalPlus {
  static ServiceFailure get notInitialized => SignalPlusState.notInitialized;

  static bool get isInitialized => SignalPlusState.runtime.isSome();

  static Future<Either<ServiceFailure, Unit>> init(final SignalPlusConfig config) => SignalPlusState.init(config);

  static Future<void> dispose() => SignalPlusState.dispose();

  static StreamSubscription<RemoteMessage> onMessage(final void Function(RemoteMessage message) handler) =>
      SignalPlusState.messages.stream.listen(handler);

  static StreamSubscription<NotificationPayload> onNotificationTap(
    final void Function(NotificationPayload payload) handler,
  ) {
    final StreamSubscription<NotificationPayload> subscription = SignalPlusState.taps.stream.listen(handler);
    SignalPlusState.deliverLaunch();
    return subscription;
  }

  static Future<Either<ServiceFailure, Unit>> onBackgroundMessage(final BackgroundHandler handler) async =>
      (await RepositoryGuard.guard(KitLogger.debug(), () async {
        await SignalPlusState.prepare();
        return BackgroundSettings.saveHandler(SignalPlusState.local, handler);
      }, BackgroundSettings.notTopLevel.operation)).flatMap(identity);

  static Future<Either<ServiceFailure, PushPermission>> requestPermission() =>
      SignalPlusState.withPush((final PushPort push) => push.requestPermission(), Operations.requestPermission);

  static Future<Either<ServiceFailure, PushPermission>> permission() =>
      SignalPlusState.withPush((final PushPort push) => push.permission(), Operations.permission);

  static Future<Either<ServiceFailure, String>> token() =>
      SignalPlusState.withPush((final PushPort push) => push.token(), Operations.token);

  static Future<Either<ServiceFailure, Unit>> deleteToken() => SignalPlusState.withPush(
    (final PushPort push) => push.deleteToken().then((final void _) => unit),
    Operations.deleteToken,
  );

  static Future<Either<ServiceFailure, Unit>> clearNotifications() => SignalPlusState.withPush(
    (final PushPort push) => push.clearNotifications().then((final void _) => unit),
    Operations.clearNotifications,
  );

  static Future<Either<ServiceFailure, SdkInstallationEntity>> setLocale(final ServiceLocale locale) =>
      SignalPlusState.setLocale(locale);

  static Future<Either<ServiceFailure, SdkInstallationEntity>> login(final String externalId) =>
      SignalPlusState.withRuntime((final SignalPlusRuntime value) => value.login(externalId));

  static Future<Either<ServiceFailure, SdkInstallationEntity>> logout() =>
      SignalPlusState.withRuntime((final SignalPlusRuntime value) => value.logout());

  static Future<Either<ServiceFailure, String>> installationId() => RepositoryGuard.guard(KitLogger.debug(), () async {
    await SignalPlusState.prepare();
    return SignalPlusState.installationIds.read();
  }, Operations.storage);

  static Future<Either<ServiceFailure, Option<String>>> externalId() =>
      RepositoryGuard.guard(KitLogger.debug(), () async {
        await SignalPlusState.prepare();
        return SignalPlusState.externalIds.read();
      }, Operations.storage);

  static Future<Either<ServiceFailure, PreferencesEntity>> preferences() => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.preferences.getPreferences(auth),
  );

  static Future<Either<ServiceFailure, UpdatedPreferencesEntity>> updatePreferences(
    final List<CategoryChoiceEntity> choices,
  ) => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.preferences.updatePreferences(auth, choices),
  );

  static Future<Either<ServiceFailure, CategoryPreferenceEntity>> categoryPreference(final String key) async =>
      (await preferences()).flatMap((final PreferencesEntity value) => CategorySwitch.find(value.categories, key));

  static Future<Either<ServiceFailure, CategoryPreferenceEntity>> setCategoryEnabled(
    final String key, {
    required final bool enabled,
  }) async => (await updatePreferences(<CategoryChoiceEntity>[
    CategoryChoiceEntity(key: key, enabled: enabled),
  ])).flatMap((final UpdatedPreferencesEntity value) => CategorySwitch.applied(value, key));

  static Future<Either<ServiceFailure, CategoryPreferenceEntity>> toggleCategory(final String key) async =>
      (await categoryPreference(key)).match(
        (final ServiceFailure failure) async => Left(failure),
        (final CategoryPreferenceEntity current) => CategorySwitch.flip(current).match(
          () async => Left(CategorySwitch.rejected(ServiceErrorCodes.categoryLocked)),
          (final CategoryChoiceEntity choice) => setCategoryEnabled(key, enabled: choice.enabled),
        ),
      );

  static Future<Either<ServiceFailure, PreferencesEntity>> setQuietHours(final QuietHoursEntity quietHours) =>
      SignalPlusState.withDevice(
        (final SignalPlusRuntime value, final DeviceAuth auth) =>
            value.client.preferences.setQuietHours(auth, quietHours),
      );

  static Future<Either<ServiceFailure, PreferencesEntity>> muteAll() => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.preferences.muteAll(auth),
  );

  static Future<Either<ServiceFailure, PreferencesEntity>> unmuteAll() => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.preferences.unmuteAll(auth),
  );

  static Future<Either<ServiceFailure, PreferencesEntity>> clearQuietHours() => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.preferences.clearQuietHours(auth),
  );

  static Future<Either<ServiceFailure, List<String>>> topics() =>
      SignalPlusState.withRuntime((final SignalPlusRuntime value) => value.client.topics.availableTopics());

  static Future<Either<ServiceFailure, List<String>>> recipientTopics() => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.topics.recipientTopics(auth),
  );

  static Future<Either<ServiceFailure, List<String>>> subscribe(final String topic) => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.topics.subscribe(auth, topic),
  );

  static Future<Either<ServiceFailure, List<String>>> unsubscribe(final String topic) => SignalPlusState.withDevice(
    (final SignalPlusRuntime value, final DeviceAuth auth) => value.client.topics.unsubscribe(auth, topic),
  );

  static Future<Either<ServiceFailure, bool>> reportOpened(final NotificationPayload payload) =>
      SignalPlusState.withRuntime((final SignalPlusRuntime value) => value.reportOpened(payload));

  static Future<Either<ServiceFailure, List<CategoryEntity>>> categories({final bool createChannels = true}) =>
      SignalPlusState.withRuntime((final SignalPlusRuntime value) => value.categories(createChannels: createChannels));
}
