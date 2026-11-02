import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kits/domain_kit.dart';

abstract class KeyValueStore {
  Future<Option<String>> read(final String key);

  Future<void> write(final String key, final String value);
}

final class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<Option<String>> read(final String key) async => Option.fromNullable(await storage.read(key: key));

  @override
  Future<void> write(final String key, final String value) => storage.write(key: key, value: value);
}

final class PreferencesKeyValueStore implements KeyValueStore {
  const PreferencesKeyValueStore();

  @override
  Future<Option<String>> read(final String key) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return Option.fromNullable(preferences.getString(key));
  }

  @override
  Future<void> write(final String key, final String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}
