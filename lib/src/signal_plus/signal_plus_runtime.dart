import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/domain/entities/catalog.dart';
import '../api/domain/entities/device_auth.dart';
import '../api/domain/entities/enums.dart';
import '../api/domain/entities/installation.dart';
import '../api/domain/entities/notification.dart';
import '../api/signalplus_client.dart';
import '../core/kits/data_kit.dart';
import '../device/device_snapshot.dart';
import '../device/installation_id_store.dart';
import '../push/messages/extensions.dart';
import '../push/models/notification_payload.dart';
import '../push/models/push_settings.dart';
import '../push/notification/notification_channel.dart';
import '../push/push_port.dart';
import 'signal_plus_config.dart';

abstract final class Operations {
  static const String token = 'GET_TOKEN_ERROR';
  static const String permission = 'PERMISSION_STATUS_ERROR';
  static const String requestPermission = 'REQUEST_PERMISSION_ERROR';
  static const String deleteToken = 'DELETE_TOKEN_ERROR';
  static const String clearNotifications = 'CLEAR_NOTIFICATIONS_ERROR';
  static const String createChannels = 'CREATE_CATEGORY_CHANNELS_ERROR';
  static const String init = 'SIGNALPLUS_INIT_ERROR';
  static const String storage = 'SIGNALPLUS_STORAGE_ERROR';
}

final class SignalPlusRuntime {
  SignalPlusRuntime({
    required this.config,
    required this.settings,
    required this.push,
    required this.client,
    required this.installationIds,
    required this.externalIds,
    required this.device,
  }) : logger = config.log;

  static const List<String> lostDevice = <String>[ServiceErrorCodes.installationNotFound];

  final SignalPlusConfig config;

  final PushSettings settings;

  final PushPort push;

  final SignalPlusClient client;

  final InstallationIdStore installationIds;

  final ExternalIdStore externalIds;

  final DeviceSnapshotReader device;

  final KitLogger logger;

  final List<StreamSubscription<Object>> subscriptions = <StreamSubscription<Object>>[];

  Option<ServiceLocale> locale = const None();

  Option<RegisterInstallationEntity> lastSent = const None();

  Future<void> queue = Future<void>.value();

  bool categoryChannels = false;

  ServiceLocale get currentLocale => locale.getOrElse(() => config.language);

  Future<Either<ServiceFailure, SdkInstallationEntity>> registerDevice({required final ServiceLocale locale}) =>
      serialized(() => register(locale));

  Future<Either<ServiceFailure, bool>> resync() => serialized(
    () => locale.match(() async => const Right<ServiceFailure, bool>(false), (final ServiceLocale language) async {
      final Either<ServiceFailure, RegisterInstallationEntity> body = await registrationFor(language);
      return body.match(Left.new, (final RegisterInstallationEntity entity) async {
        if (lastSent == some(entity)) return const Right<ServiceFailure, bool>(false);
        return (await send(entity)).map((final SdkInstallationEntity _) => true);
      });
    }),
  );

  Future<Either<ServiceFailure, SdkInstallationEntity>> login(final String externalId) => serialized(() async {
    final Either<ServiceFailure, SdkInstallationEntity> result = await onDevice(
      (final DeviceAuth auth) => client.installations.login(auth, externalId: externalId),
    );
    if (result.isRight()) await externalIds.save(externalId);
    return result;
  });

  Future<Either<ServiceFailure, SdkInstallationEntity>> logout() => serialized(() async {
    final Either<ServiceFailure, SdkInstallationEntity> result = await onDevice(client.installations.logout);
    if (result.isRight()) await externalIds.clear();
    return result;
  });

  Future<Either<ServiceFailure, T>> personal<T>(
    final Future<Either<ServiceFailure, T>> Function(DeviceAuth auth) call,
  ) => serialized(() async {
    final Either<ServiceFailure, T> result = await onDevice(call);
    if (refused(result, const <String>[ServiceErrorCodes.notSignedIn])) await externalIds.clear();
    return result;
  });

  Future<Either<ServiceFailure, bool>> reportOpened(final NotificationPayload payload) => payload.notifyId.match(
    () async => const Right<ServiceFailure, bool>(false),
    (final String notifyId) => serialized(
      () => onDevice(
        (final DeviceAuth auth) => client.notifications.reportEvent(
          auth,
          notifyId,
          DeliveryEventEntity(type: DeliveryEventType.opened, at: Some(DateTime.now())),
        ),
      ),
    ),
  );

  Future<Either<ServiceFailure, List<CategoryEntity>>> categories({required final bool createChannels}) async {
    final Either<ServiceFailure, List<CategoryEntity>> result = await client.catalog.listCategories();
    if (!createChannels) return result;
    return result.match(Left.new, (final List<CategoryEntity> categories) async {
      final Either<ServiceFailure, Unit> created = await guard(() async {
        final List<CategoryEntity> general = categories.where(isGeneral).toList();
        await push.deleteChannels(<String>[
          for (final CategoryEntity category in general)
            if (category.channelId != PushSettings.channelId) category.channelId,
        ]);
        await push.registerChannels(<ChannelSpec>[
          for (final CategoryEntity category in categories.where((final CategoryEntity item) => !isGeneral(item)))
            ChannelSpec(
              id: category.channelId,
              name: category.name,
              description: category.description.getOrElse(() => ''),
              importance: ChannelSpec.importanceFor(category.lane),
            ),
        ]);
        return unit;
      }, Operations.createChannels);
      if (created.isRight()) categoryChannels = true;
      return created.map((final Unit _) => categories);
    });
  }

  /// A category that means the same as the default channel shares it, so Android does not list "General" twice.
  /// What the service sends to its own channel id falls back to the default channel, which the manifest names.
  bool isGeneral(final CategoryEntity category) {
    final Set<String> names = <String>{
      for (final ServiceLocale language in ServiceLocale.values) settings.localized(language).channelName.toLowerCase(),
    };
    return <String>{
          category.key,
          category.channelId,
        }.any((final String id) => id.toLowerCase() == generalKey || id == PushSettings.channelId) ||
        names.contains(category.name.trim().toLowerCase());
  }

  static const String generalKey = 'general';

  /// One Android channel per category, brought in line with the dashboard on every start.
  Future<void> syncChannels() async {
    if (defaultTargetPlatform.isAndroid) await categories(createChannels: true);
  }

  Future<void> refreshChannels(final ServiceLocale language) async {
    await guard(() async {
      await push.registerChannels(<ChannelSpec>[ChannelSpec.fromSettings(settings.localized(language))]);
      return unit;
    }, Operations.createChannels);
    if (categoryChannels) await categories(createChannels: true);
  }

  Future<Either<ServiceFailure, T>> onDevice<T>(
    final Future<Either<ServiceFailure, T>> Function(DeviceAuth auth) call,
  ) async {
    final Either<ServiceFailure, T> first = await call(await currentDevice());
    if (!refused(first, lostDevice)) return first;
    final Either<ServiceFailure, SdkInstallationEntity> registered = await register(currentLocale);
    return registered.match(Left.new, (final SdkInstallationEntity _) async => call(await currentDevice()));
  }

  Future<Either<ServiceFailure, SdkInstallationEntity>> register(final ServiceLocale language) async {
    locale = some(language);
    client.useLocale(language);
    final Either<ServiceFailure, RegisterInstallationEntity> body = await registrationFor(language);
    return body.match(Left.new, send);
  }

  Future<Either<ServiceFailure, SdkInstallationEntity>> send(final RegisterInstallationEntity entity) async {
    final Either<ServiceFailure, SdkInstallationEntity> result = await client.installations.register(
      await currentDevice(),
      entity,
    );
    if (result.isRight()) lastSent = some(entity);
    return result;
  }

  Future<DeviceAuth> currentDevice() async => DeviceAuth(installationId: await installationIds.read());

  Future<Either<ServiceFailure, RegisterInstallationEntity>> registrationFor(final ServiceLocale language) async {
    final Either<ServiceFailure, String> token = await push.events.latestToken.match(
      () => guard(push.token, Operations.token),
      (final String value) async => Right<ServiceFailure, String>(value),
    );
    final Either<ServiceFailure, PushPermission> permission = await guard(push.permission, Operations.permission);
    final DeviceSnapshot snapshot = await device.read();
    return token.flatMap(
      (final String value) => permission.map(
        (final PushPermission status) => RegisterInstallationEntity(
          platform: snapshot.platform,
          token: value,
          pushPermission: status,
          appVersion: snapshot.appVersion,
          buildNumber: snapshot.buildNumber,
          locale: language.wire,
          timeZone: snapshot.timeZone,
          osVersion: snapshot.osVersion,
          deviceModel: snapshot.deviceModel,
        ),
      ),
    );
  }

  static bool refused<T>(final Either<ServiceFailure, T> result, final List<String> codes) =>
      result.match((final ServiceFailure failure) => codes.any(failure.hasCode), (final T _) => false);

  Future<Either<ServiceFailure, T>> guard<T>(final Future<T> Function() run, final String operation) =>
      RepositoryGuard.guard(logger, run, operation);

  Future<T> serialized<T>(final Future<T> Function() run) {
    final Future<T> next = queue.then((final void _) => run());
    queue = next.then((final T _) {}, onError: (final Object _) {});
    return next;
  }

  Future<void> dispose() async {
    await Future.wait(subscriptions.map((final StreamSubscription<Object> item) => item.cancel()));
    subscriptions.clear();
    await push.dispose();
    client.close();
  }
}
