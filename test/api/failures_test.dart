import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/api/client/api_config.dart';
import 'package:signalplus/src/api/domain/entities/enums.dart';
import 'package:signalplus/src/api/domain/entities/installation.dart';
import 'package:signalplus/src/api/signalplus_client.dart';

import '../support/api_harness.dart';

void main() {
  test('the stable code comes from Error[0] and the message from Message', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'GET /sdk/v1/categories',
      StubResponse.failure(401, <String>['AppIdInvalid'], message: 'المعرّف غير صالح'),
    );

    final ServiceFailure failure = leftOf(await harness.client.catalog.listCategories());

    expect(failure.type, FailureType.unauthenticated);
    expect(failure.statusCode, 401);
    expect(failure.hasCode(ServiceErrorCodes.appIdInvalid), isTrue);
    expect(failure.message, 'المعرّف غير صالح');
    expect(failure.operation, 'LIST_CATEGORIES_ERROR');
  });

  test('a validation failure exposes each field error', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'PUT /sdk/v1/installations/i-1',
      StubResponse.failure(
        400,
        <String>['ValidationFailed'],
        data: <String, dynamic>{
          'Errors': <Map<String, String>>[
            <String, String>{'Property': 'Token', 'Code': 'Required', 'Message': 'التوكن مطلوب'},
          ],
        },
      ),
    );

    final ServiceFailure failure = leftOf(
      await harness.client.installations.register(
        ApiHarness.device,
        const RegisterInstallationEntity(
          platform: DevicePlatform.android,
          token: '',
          pushPermission: PushPermission.granted,
          appVersion: '1',
          buildNumber: '1',
          locale: 'ar',
          timeZone: 'Asia/Baghdad',
        ),
      ),
    );

    expect(failure.hasCode(ServiceErrorCodes.validationFailed), isTrue);
    expect(failure.hasCode('Required'), isTrue);
    expect(failure.fieldError('token').map((final FieldError error) => error.message), const Some('التوكن مطلوب'));
  });

  test('an internal error keeps its correlation id', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('GET /sdk/v1/categories', StubResponse.failure(500, <String>['InternalError', 'CorrelationId=abc-123']));

    final ServiceFailure failure = leftOf(await harness.client.catalog.listCategories());

    expect(failure.correlationId, const Some('abc-123'));
    expect(failure.hasCode(ServiceErrorCodes.internalError), isTrue);
  });

  test('a lost connection becomes a connection failure', () async {
    final ApiHarness harness = ApiHarness()..thrown = http.ClientException('offline');

    final ServiceFailure failure = leftOf(await harness.client.catalog.listCategories());

    expect(failure.type, FailureType.connection);
    expect(failure.type.isNetwork, isTrue);
  });

  test('a call slower than the timeout becomes a timeout failure', () async {
    final ApiHarness harness = ApiHarness(
      config: const ApiConfig(appId: 'a', locale: ServiceLocale.ar, timeout: Duration(milliseconds: 10)),
    )..thrown = TimeoutException('slow');

    expect(leftOf(await harness.client.catalog.listCategories()).type, FailureType.timeout);
  });

  test('a body that stalls after the headers arrive also becomes a timeout failure', () async {
    final StreamController<List<int>> body = StreamController<List<int>>();
    addTearDown(body.close);
    final SignalPlusClient client = SignalPlusClient.create(
      const ApiConfig(appId: 'a', locale: ServiceLocale.ar, timeout: Duration(milliseconds: 10)),
      client: Some(
        MockClient.streaming(
          (final http.BaseRequest request, final http.ByteStream _) async => http.StreamedResponse(body.stream, 200),
        ),
      ),
    );

    expect(leftOf(await client.catalog.listCategories()).type, FailureType.timeout);
  });

  test('a success body that does not match the schema becomes a decoding failure', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'GET /sdk/v1/installations/i-1/recipient/preferences',
      StubResponse.data(<String, dynamic>{'Categories': 5}),
    );

    expect(leftOf(await harness.client.preferences.getPreferences(ApiHarness.device)).type, FailureType.decoding);
  });

  test('a call with nobody signed in answers NotSignedIn', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'GET /sdk/v1/installations/i-1/recipient/preferences',
      StubResponse.failure(403, <String>['NotSignedIn']),
    );

    final ServiceFailure failure = leftOf(await harness.client.preferences.getPreferences(ApiHarness.device));

    expect(failure.statusCode, 403);
    expect(failure.hasCode(ServiceErrorCodes.notSignedIn), isTrue);
  });
}
