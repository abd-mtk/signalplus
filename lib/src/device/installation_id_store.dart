import 'package:uuid/uuid.dart';

import '../core/kits/domain_kit.dart';
import '../core/storage/key_value_store.dart';
import '../core/utils/memo.dart';

final class InstallationIdStore {
  InstallationIdStore({required this.store, final Option<String Function()> newId = const None()})
    : newId = newId.getOrElse(() => randomId);

  static const String key = 'signalplus.installation_id';

  final KeyValueStore store;

  final String Function() newId;

  final Memo<String> cached = Memo<String>();

  Future<String> read() => cached(load);

  Future<String> load() async {
    final Option<String> stored = (await store.read(key)).filter((final String value) => value.isNotEmpty);
    return stored.match(() async {
      final String created = newId();
      await store.write(key, created);
      return created;
    }, (final String value) async => value);
  }

  static String randomId() => const Uuid().v4();
}

base class StoredValue {
  StoredValue({required this.store, required this.storageKey});

  final KeyValueStore store;

  final String storageKey;

  final Memo<Option<String>> cached = Memo<Option<String>>();

  Future<Option<String>> read() =>
      cached(() async => (await store.read(storageKey)).filter((final String item) => item.isNotEmpty));

  Future<void> save(final String value) async {
    await store.write(storageKey, value);
    cached.set(some(value));
  }

  Future<void> clear() async {
    await store.write(storageKey, '');
    cached.set(const None());
  }
}

final class ExternalIdStore extends StoredValue {
  ExternalIdStore({required super.store}) : super(storageKey: key);

  static const String key = 'signalplus.external_id';
}

final class CategoryChannelStore extends StoredValue {
  CategoryChannelStore({required super.store}) : super(storageKey: key);

  static const String key = 'signalplus.category_channels';

  Future<List<String>> ids() async =>
      (await read()).map((final String value) => value.split(',')).getOrElse(() => const <String>[]);

  Future<void> remember(final List<String> ids) => ids.isEmpty ? clear() : save(ids.join(','));
}
