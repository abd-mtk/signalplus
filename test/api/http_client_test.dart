import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/api/client/api_config.dart';
import '../support/api_harness.dart';

void main() {
  test('every call carries the App ID, json accept and the configured language, never an Authorization', () async {
    final ApiHarness harness = ApiHarness(
      config: const ApiConfig(appId: ApiHarness.appId, locale: ServiceLocale.en),
    );
    harness.on('GET /sdk/v1/categories', StubResponse.data(fixture('categories')));

    await harness.client.catalog.listCategories();

    expect(harness.last.headers['X-SignalPlus-App-Id'], ApiHarness.appId);
    expect(harness.last.headers['Accept-Language'], 'en');
    expect(harness.last.headers['Accept'], 'application/json');
    expect(harness.last.headers.containsKey('Authorization'), isFalse);
    expect(harness.last.headers.containsKey('X-SignalPlus-Installation-Secret'), isFalse);
    expect(harness.last.url.host, 'api.signal-plus.kog.technology');
  });

  test('device calls name the device only by its installation id in the path', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('GET /sdk/v1/installations/i-1/recipient/topics', StubResponse.data(fixture('topics')));

    await harness.client.topics.recipientTopics(ApiHarness.device);

    expect(harness.last.url.path, '/sdk/v1/installations/i-1/recipient/topics');
    expect(harness.last.headers['X-SignalPlus-App-Id'], ApiHarness.appId);
    expect(harness.last.headers.containsKey('X-SignalPlus-Installation-Secret'), isFalse);
  });

  test('a custom base url keeps its own path prefix before sdk/v1', () async {
    final ApiHarness harness = ApiHarness(
      config: const ApiConfig(appId: 'a', locale: ServiceLocale.ar, baseUrl: 'https://edge.example.com/signalplus/'),
    );
    harness.on('GET /signalplus/sdk/v1/categories', StubResponse.data(fixture('categories')));

    expect((await harness.client.catalog.listCategories()).isRight(), isTrue);
    expect(harness.last.url.toString(), 'https://edge.example.com/signalplus/sdk/v1/categories');
  });

  test('path segments are encoded so names with separators stay one segment', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('PUT /sdk/v1/installations/i-1/recipient/topics/a%2Fb', StubResponse.data(fixture('topics')));

    await harness.client.topics.subscribe(ApiHarness.device, 'a/b');

    expect(harness.last.url.pathSegments, <String>['sdk', 'v1', 'installations', 'i-1', 'recipient', 'topics', 'a/b']);
  });

  test('no call sends an idempotency key', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'POST /sdk/v1/installations/i-1/logout',
      StubResponse.data(<String, dynamic>{
        'InstallationId': 'i-1',
        'ExternalId': null,
        'TokenStatus': 'Valid',
        'PushPermission': 'Granted',
      }),
    );

    await harness.client.installations.logout(ApiHarness.device);

    expect(harness.last.headers.containsKey('Idempotency-Key'), isFalse);
  });
}
