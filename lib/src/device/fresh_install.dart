import '../core/storage/key_value_store.dart';

abstract final class FreshInstall {
  static const String markerKey = 'signalplus.installed';

  static Future<bool> resetIfNew({
    required final KeyValueStore secure,
    required final KeyValueStore local,
    required final List<String> keys,
  }) async {
    if ((await local.read(markerKey)).isSome()) return false;
    for (final String key in keys) {
      await secure.write(key, '');
    }
    await local.write(markerKey, '1');
    return true;
  }
}
