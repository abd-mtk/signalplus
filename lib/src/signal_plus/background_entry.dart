import 'dart:convert';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../core/kits/domain_kit.dart';
import '../core/storage/key_value_store.dart';
import '../core/utils/json_reader.dart';
import '../push/bootstrap/signalplus_instance.dart';
import '../push/models/push_settings.dart';

typedef BackgroundHandler = Future<void> Function(RemoteMessage message);

abstract final class BackgroundSettings {
  static const String configKey = 'signalplus.background_config';
  static const String handlerKey = 'signalplus.background_handler';

  static const ServiceFailure notTopLevel = ServiceFailure(
    type: FailureType.platform,
    operation: 'BACKGROUND_HANDLER_ERROR',
    details: 'The background handler must be a top-level or static function.',
  );

  static Future<void> saveConfig(final KeyValueStore store, final PushSettings config) =>
      store.write(configKey, jsonEncode(config.toJson()));

  static Future<Option<PushSettings>> readConfig(final KeyValueStore store) async =>
      (await store.read(configKey)).flatMap((final String raw) {
        try {
          return some(PushSettings.fromJson(JsonReader.object(jsonDecode(raw))));
        } on Object {
          return const None();
        }
      });

  static Future<Either<ServiceFailure, Unit>> saveHandler(final KeyValueStore store, final BackgroundHandler handler) =>
      Option.fromNullable(PluginUtilities.getCallbackHandle(handler)).match(
        () async => const Left<ServiceFailure, Unit>(notTopLevel),
        (final CallbackHandle handle) async {
          await store.write(handlerKey, '${handle.toRawHandle()}');
          return const Right<ServiceFailure, Unit>(unit);
        },
      );

  static Future<Option<BackgroundHandler>> readHandler(final KeyValueStore store) async =>
      (await store.read(handlerKey))
          .flatMap((final String raw) => Option.fromNullable(int.tryParse(raw)))
          .flatMap(
            (final int raw) =>
                Option.fromNullable(PluginUtilities.getCallbackFromHandle(CallbackHandle.fromRawHandle(raw))),
          )
          .flatMap(
            (final Function callback) =>
                callback is BackgroundHandler
                    ? Option<BackgroundHandler>.of(callback)
                    : const Option<BackgroundHandler>.none(),
          );
}

@pragma('vm:entry-point')
Future<void> signalPlusBackgroundEntry(final RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const KeyValueStore store = SecureKeyValueStore();
  await (await BackgroundSettings.readConfig(store)).match(
    () async {},
    (final PushSettings config) => SignalPlusInstance.showBackgroundMessage(message, config: config),
  );
  await (await BackgroundSettings.readHandler(
    store,
  )).match(() async {}, (final BackgroundHandler handler) => handler(message));
}
