import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../api/domain/entities/device_auth.dart';
import '../api/domain/entities/enums.dart';
import '../api/domain/entities/installation.dart';
import '../api/signalplus_client.dart';
import '../core/kits/data_kit.dart';
import '../core/storage/key_value_store.dart';
import '../device/device_snapshot.dart';
import '../device/fresh_install.dart';
import '../device/installation_id_store.dart';
import '../push/bootstrap/signalplus_instance.dart';
import '../push/models/notification_payload.dart';
import '../push/models/push_settings.dart';
import '../push/push_port.dart';
import 'background_entry.dart';
import 'signal_plus_config.dart';
import 'signal_plus_runtime.dart';

typedef PushStarter = Future<PushPort> Function(SignalPlusConfig config, PushSettings settings);

typedef ClientFactory = SignalPlusClient Function(SignalPlusConfig config);

typedef DeviceFactory = DeviceSnapshotReader Function(SignalPlusConfig config);

abstract final class SignalPlusState {
  static Option<SignalPlusRuntime> runtime = const None();

  static Option<Future<Either<ServiceFailure, Unit>>> starting = const None();

  static Option<Future<bool>> prepared = const None();

  static Option<NotificationPayload> pendingLaunch = const None();

  static KeyValueStore secure = const SecureKeyValueStore();

  static KeyValueStore local = const PreferencesKeyValueStore();

  static PushStarter startPush = startFirebase;

  static ClientFactory createClient = defaultClient;

  static DeviceFactory createDevice = defaultDevice;

  static void Function(void Function() run) launchScheduler = afterFirstFrame;

  static final StreamController<RemoteMessage> messages = StreamController<RemoteMessage>.broadcast(sync: true);

  static final StreamController<NotificationPayload> taps = StreamController<NotificationPayload>.broadcast(sync: true);

  static InstallationIdStore installationIds = InstallationIdStore(store: secure);

  static ExternalIdStore externalIds = ExternalIdStore(store: secure);

  static Future<Either<ServiceFailure, Unit>> init(final SignalPlusConfig config) {
    if (runtime.isSome()) return Future<Either<ServiceFailure, Unit>>.value(const Right(unit));
    return starting.getOrElse(() {
      final Future<Either<ServiceFailure, Unit>> run = RepositoryGuard.guard(config.log, () async {
        await prepare();
        final DeviceSnapshotReader device = createDevice(config);
        final String appName = await device.read().then(
          (final DeviceSnapshot snapshot) => snapshot.appName,
          onError: (final Object _) => '',
        );
        final PushSettings settings = config.settings(appName: appName);
        final PushPort push = await startPush(config, settings);
        await BackgroundSettings.saveConfig(secure, settings);
        final SignalPlusRuntime value = SignalPlusRuntime(
          config: config,
          settings: settings,
          push: push,
          client: createClient(config),
          installationIds: installationIds,
          externalIds: externalIds,
          device: device,
        );
        attach(value);
        unawaited(value.syncChannels());
        if (config.registerOnStart) unawaited(value.registerDevice(locale: config.language));
        return unit;
      }, Operations.init).whenComplete(() => starting = const None());
      starting = some(run);
      return run;
    });
  }

  static Future<Either<ServiceFailure, SdkInstallationEntity>> setLocale(final ServiceLocale locale) =>
      withRuntime((final SignalPlusRuntime value) async {
        final Either<ServiceFailure, SdkInstallationEntity> result = await value.registerDevice(locale: locale);
        await value.refreshChannels(locale);
        await value.guard(() async {
          await BackgroundSettings.saveConfig(secure, value.settings.localized(locale));
          return unit;
        }, Operations.storage);
        return result;
      });

  static SignalPlusClient defaultClient(final SignalPlusConfig config) =>
      SignalPlusClient.create(config.api, logger: config.log);

  static DeviceSnapshotReader defaultDevice(final SignalPlusConfig config) =>
      PlatformDeviceSnapshotReader(logger: config.log);

  static Future<PushPort> startFirebase(final SignalPlusConfig config, final PushSettings settings) =>
      SignalPlusInstance.start(
        config: settings,
        firebaseOptions: config.firebaseOptions,
        backgroundHandler: const Some(signalPlusBackgroundEntry),
      );

  static Future<bool> prepare() => prepared.getOrElse(() {
    WidgetsFlutterBinding.ensureInitialized();
    final Future<bool> check = FreshInstall.resetIfNew(
      secure: secure,
      local: local,
      keys: const <String>[
        InstallationIdStore.key,
        ExternalIdStore.key,
        BackgroundSettings.configKey,
        BackgroundSettings.handlerKey,
      ],
    );
    prepared = some(check);
    return check;
  });

  static void attach(final SignalPlusRuntime value) {
    runtime = some(value);
    value.subscriptions.addAll(<StreamSubscription<Object>>[
      value.push.events.messages.listen(messages.add),
      value.push.events.taps.listen((final NotificationPayload payload) {
        taps.add(payload);
        unawaited(value.reportOpened(payload));
      }),
      value.push.events.tokens.listen((final String _) => unawaited(value.resync())),
      value.push.events.permissions.listen((final PushPermission _) => unawaited(value.resync())),
    ]);
    pendingLaunch = value.push.takeInitialNotification();
    pendingLaunch.match(() {}, (final NotificationPayload payload) => unawaited(value.reportOpened(payload)));
    deliverLaunch();
  }

  static void deliverLaunch() {
    if (!taps.hasListener) return;
    pendingLaunch.match(() {}, (final NotificationPayload payload) {
      pendingLaunch = const None();
      launchScheduler(() => taps.add(payload));
    });
  }

  static void afterFirstFrame(final void Function() run) {
    WidgetsBinding.instance
      ..addPostFrameCallback((final Duration _) => run())
      ..ensureVisualUpdate();
  }

  static Future<Either<ServiceFailure, T>> withRuntime<T>(
    final Future<Either<ServiceFailure, T>> Function(SignalPlusRuntime value) run,
  ) => runtime.match(() async => Left<ServiceFailure, T>(notInitialized), run);

  static Future<Either<ServiceFailure, T>> withDevice<T>(
    final Future<Either<ServiceFailure, T>> Function(SignalPlusRuntime value, DeviceAuth auth) run,
  ) => withRuntime((final SignalPlusRuntime value) => value.personal((final DeviceAuth auth) => run(value, auth)));

  static Future<void> dispose() async {
    await runtime.match(() async {}, (final SignalPlusRuntime value) => value.dispose());
    runtime = const None();
    starting = const None();
    pendingLaunch = const None();
  }

  @visibleForTesting
  static Future<void> reset({required final KeyValueStore secureStore, required final KeyValueStore localStore}) async {
    await dispose();
    prepared = const None();
    secure = secureStore;
    local = localStore;
    installationIds = InstallationIdStore(store: secureStore);
    externalIds = ExternalIdStore(store: secureStore);
    createClient = defaultClient;
    createDevice = defaultDevice;
  }

  static const ServiceFailure notInitialized = ServiceFailure(
    type: FailureType.platform,
    operation: 'SIGNALPLUS_NOT_INITIALIZED',
    details: 'Call SignalPlus.init() first.',
  );
}
