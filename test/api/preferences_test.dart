import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import '../support/api_harness.dart';

void main() {
  test('preferences come with categories and quiet hours', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('GET /sdk/v1/installations/i-1/recipient/preferences', StubResponse.data(fixture('preferences')));

    final PreferencesEntity preferences = rightOf(await harness.client.preferences.getPreferences(ApiHarness.device));

    expect(preferences.categories.map((final CategoryPreferenceEntity category) => category.key), <String>[
      'Orders',
      'Promotions',
    ]);
    expect(
      preferences.quietHours.map((final QuietHoursEntity hours) => hours.props).toNullable(),
      const QuietHoursEntity(start: '22:00', end: '07:00', days: <WeekDay>[WeekDay.fri, WeekDay.sat]).props,
    );
    expect(preferences.categories.map((final CategoryPreferenceEntity category) => category.description), <Object>[
      const Some('تحديثات الطلب'),
      const None(),
    ]);
    expect(preferences.muted, isFalse);
  });

  test('a service without Muted reads as not muted', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'GET /sdk/v1/installations/i-1/recipient/preferences',
      StubResponse.data(<String, dynamic>{'Categories': <dynamic>[], 'QuietHours': null}),
    );

    expect(rightOf(await harness.client.preferences.getPreferences(ApiHarness.device)).muted, isFalse);
  });

  test('muting and unmuting answer the settings with Muted', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'PUT /sdk/v1/installations/i-1/recipient/mute',
      StubResponse.data(<String, dynamic>{'Muted': true, 'Categories': <dynamic>[], 'QuietHours': null}),
    );
    harness.on(
      'DELETE /sdk/v1/installations/i-1/recipient/mute',
      StubResponse.data(<String, dynamic>{'Muted': false, 'Categories': <dynamic>[], 'QuietHours': null}),
    );

    expect(rightOf(await harness.client.preferences.muteAll(ApiHarness.device)).muted, isTrue);
    expect(harness.last.json, isNull);
    expect(rightOf(await harness.client.preferences.unmuteAll(ApiHarness.device)).muted, isFalse);
    expect(harness.routesCalled, <String>[
      'PUT /sdk/v1/installations/i-1/recipient/mute',
      'DELETE /sdk/v1/installations/i-1/recipient/mute',
    ]);
  });

  test('updating reports locked and unknown categories as rejected', () async {
    final ApiHarness harness = ApiHarness();
    harness.on(
      'PUT /sdk/v1/installations/i-1/recipient/preferences',
      StubResponse.data(fixture('updated_preferences')),
    );

    final UpdatedPreferencesEntity updated = rightOf(
      await harness.client.preferences.updatePreferences(ApiHarness.device, const <CategoryChoiceEntity>[
        CategoryChoiceEntity(key: 'Promotions', enabled: true),
      ]),
    );

    expect(harness.last.json, <String, dynamic>{
      'Categories': <dynamic>[
        <String, dynamic>{'Key': 'Promotions', 'Enabled': true},
      ],
    });
    expect(updated.rejected.map((final RejectedChoiceEntity choice) => choice.error), <String>[
      ServiceErrorCodes.categoryLocked,
      ServiceErrorCodes.categoryUnknown,
    ]);
  });

  test('quiet hours are set with their days, and clearing answers the settings', () async {
    final ApiHarness harness = ApiHarness();
    harness.on('PUT /sdk/v1/installations/i-1/recipient/quiet-hours', StubResponse.data(fixture('preferences')));
    harness.on(
      'DELETE /sdk/v1/installations/i-1/recipient/quiet-hours',
      StubResponse.data(<String, dynamic>{'Categories': <dynamic>[], 'QuietHours': null}),
    );

    await harness.client.preferences.setQuietHours(
      ApiHarness.device,
      const QuietHoursEntity(start: '22:00', end: '07:00', days: <WeekDay>[WeekDay.fri]),
    );
    expect(harness.last.json, <String, dynamic>{
      'Start': '22:00',
      'End': '07:00',
      'Days': <dynamic>['Fri'],
    });

    expect(rightOf(await harness.client.preferences.clearQuietHours(ApiHarness.device)).quietHours, const None());
  });
}
