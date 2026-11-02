import '../../../core/kits/data_kit.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/preferences.dart';

abstract final class PreferencesModel {
  static PreferencesEntity fromJson(final JsonMap json) => PreferencesEntity(
    categories: JsonReader.list(json, 'Categories', category),
    quietHours: JsonReader.optMap(json, 'QuietHours').map(quietHours),
    muted: JsonReader.optBoolean(json, 'Muted').getOrElse(() => false),
  );

  static UpdatedPreferencesEntity updatedFromJson(final JsonMap json) {
    final PreferencesEntity preferences = fromJson(json);
    return UpdatedPreferencesEntity(
      categories: preferences.categories,
      quietHours: preferences.quietHours,
      muted: preferences.muted,
      rejected: JsonReader.list(json, 'Rejected', (final Object? item) {
        final JsonMap rejected = JsonReader.object(item, 'Rejected');
        return RejectedChoiceEntity(
          key: JsonReader.string(rejected, 'Key'),
          error: JsonReader.string(rejected, 'Error'),
        );
      }),
    );
  }

  static CategoryPreferenceEntity category(final Object? item) {
    final JsonMap json = JsonReader.object(item, 'CategoryPreference');
    return CategoryPreferenceEntity(
      key: JsonReader.string(json, 'Key'),
      name: JsonReader.string(json, 'Name'),
      description: JsonReader.optString(json, 'Description'),
      enabled: JsonReader.boolean(json, 'Enabled'),
      locked: JsonReader.boolean(json, 'Locked'),
    );
  }

  static QuietHoursEntity quietHours(final JsonMap json) => QuietHoursEntity(
    start: JsonReader.string(json, 'Start'),
    end: JsonReader.string(json, 'End'),
    days: JsonReader.strings(json, 'Days').map(WeekDay.parse).toList(growable: false),
  );

  static JsonMap quietHoursToJson(final QuietHoursEntity entity) => <String, dynamic>{
    'Start': entity.start,
    'End': entity.end,
    'Days': entity.days.map((final WeekDay day) => day.wire).toList(growable: false),
  };

  static JsonMap choicesToJson(final List<CategoryChoiceEntity> choices) => <String, dynamic>{
    'Categories': <JsonMap>[
      for (final CategoryChoiceEntity choice in choices)
        <String, dynamic>{'Key': choice.key, 'Enabled': choice.enabled},
    ],
  };
}
