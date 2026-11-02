import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/api/domain/entities/device_auth.dart';
import 'package:signalplus/src/api/domain/entities/enums.dart';
import 'package:signalplus/src/api/domain/entities/installation.dart';

import '../support/api_harness.dart';

const RegisterInstallationEntity registration = RegisterInstallationEntity(
  platform: DevicePlatform.android,
  token: 'fcm-token',
  pushPermission: PushPermission.granted,
  appVersion: '2.3.0',
  buildNumber: '41',
  locale: 'ar',
  timeZone: 'Asia/Baghdad',
  osVersion: Some('Android 14'),
  deviceModel: Some('SM-A546E'),
);

const DeviceAuth newDevice = DeviceAuth(installationId: 'i-1');

Map<String, dynamic> view({final Object? externalId}) => <String, dynamic>{
  'InstallationId': 'i-1',
  'ExternalId': externalId,
  'TokenStatus': 'Valid',
  'PushPermission': 'Granted',
};

void main() {
  test('registering sends every device field and no ExternalId', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('PUT /sdk/v1/installations/i-1', StubResponse.data(view(), status: 201));

    final SdkInstallationEntity result = rightOf(await harness.client.installations.register(newDevice, registration));

    expect(harness.last.url.toString(), 'https://sdk.test/sdk/v1/installations/i-1');
    expect(harness.last.json, <String, dynamic>{
      'Platform': 'Android',
      'Token': 'fcm-token',
      'PushPermission': 'Granted',
      'AppVersion': '2.3.0',
      'BuildNumber': '41',
      'Locale': 'ar',
      'TimeZone': 'Asia/Baghdad',
      'OsVersion': 'Android 14',
      'DeviceModel': 'SM-A546E',
    });
    expect(result.externalId, const None());
    expect(result.tokenStatus, TokenStatus.valid);
  });

  test('login sends only the external id', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('POST /sdk/v1/installations/i-1/login', StubResponse.data(view(externalId: '123')));

    final SdkInstallationEntity signedIn = rightOf(
      await harness.client.installations.login(ApiHarness.device, externalId: '123'),
    );

    expect(harness.last.json, <String, dynamic>{'ExternalId': '123'});
    expect(signedIn.externalId, const Some('123'));
  });

  test('logout takes no body', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('POST /sdk/v1/installations/i-1/logout', StubResponse.data(view()));

    final SdkInstallationEntity result = rightOf(await harness.client.installations.logout(ApiHarness.device));

    expect(harness.last.body, isEmpty);
    expect(result.externalId, const None());
  });

  test('SDK refusals keep their codes', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('PUT /sdk/v1/installations/i-1', StubResponse.failure(401, <String>['AppIdInvalid']));
    harness.on('POST /sdk/v1/installations/i-1/login', StubResponse.failure(403, <String>['TenantSuspended']));

    final ServiceFailure unknownApp = leftOf(await harness.client.installations.register(newDevice, registration));
    final ServiceFailure suspended = leftOf(
      await harness.client.installations.login(ApiHarness.device, externalId: '123'),
    );

    expect(unknownApp.hasCode(ServiceErrorCodes.appIdInvalid), isTrue);
    expect(suspended.hasCode(ServiceErrorCodes.tenantSuspended), isTrue);
  });
}
