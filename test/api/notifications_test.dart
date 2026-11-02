import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/api/domain/entities/enums.dart';
import 'package:signalplus/src/api/domain/entities/notification.dart';
import '../support/api_harness.dart';

void main() {
  test('an open is reported for this device with its time and no installation in the body', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'POST /sdk/v1/installations/i-1/notifications/ntf_01/events',
      StubResponse.data(<String, dynamic>{'Applied': true}),
    );

    final bool applied = rightOf(
      await harness.client.notifications.reportEvent(
        ApiHarness.device,
        'ntf_01',
        DeliveryEventEntity(type: DeliveryEventType.opened, at: Some(DateTime.utc(2026, 10, 13))),
      ),
    );

    expect(applied, isTrue);
    expect(harness.last.json, <String, dynamic>{'Type': 'Opened', 'At': '2026-10-13T00:00:00.000Z'});
  });

  test('a notification that never reached this device is not applied', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'POST /sdk/v1/installations/i-1/notifications/ntf_02/events',
      StubResponse.data(<String, dynamic>{'Applied': false}),
    );

    expect(
      rightOf(
        await harness.client.notifications.reportEvent(
          ApiHarness.device,
          'ntf_02',
          const DeliveryEventEntity(type: DeliveryEventType.dismissed),
        ),
      ),
      isFalse,
    );
  });
}
