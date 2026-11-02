import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/core/storage/key_value_store.dart';
import 'package:signalplus/src/device/installation_id_store.dart';

import '../support/device_fakes.dart';

void main() {
  test('an id is created once and then reused', () async {
    final MemoryStore memory = MemoryStore();
    int created = 0;
    String next() => 'id-${++created}';

    final String first = await InstallationIdStore(store: memory, newId: Some(next)).read();
    final String again = await InstallationIdStore(store: memory, newId: Some(next)).read();

    expect(first, 'id-1');
    expect(again, 'id-1');
    expect(created, 1);
    expect(memory.values[InstallationIdStore.key], 'id-1');
  });

  test('concurrent reads share one creation', () async {
    int created = 0;
    final InstallationIdStore ids = InstallationIdStore(store: MemoryStore(), newId: Some(() => 'id-${++created}'));

    final List<String> results = await Future.wait(<Future<String>>[ids.read(), ids.read()]);

    expect(results, <String>['id-1', 'id-1']);
    expect(created, 1);
  });

  test('a failed read is tried again instead of failing for good', () async {
    final FailingOnceStore store = FailingOnceStore();
    final InstallationIdStore ids = InstallationIdStore(store: store, newId: const Some(fixedId));

    await expectLater(ids.read(), throwsA(isA<StateError>()));

    expect(await ids.read(), 'id-1');
  });

  test('the default id is a v4 uuid', () {
    expect(
      InstallationIdStore.randomId(),
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
  });
}

String fixedId() => 'id-1';

final class FailingOnceStore implements KeyValueStore {
  final MemoryStore memory = MemoryStore();

  bool failed = false;

  @override
  Future<Option<String>> read(final String key) async {
    if (failed) return memory.read(key);
    failed = true;
    throw StateError('keychain locked');
  }

  @override
  Future<void> write(final String key, final String value) => memory.write(key, value);
}
