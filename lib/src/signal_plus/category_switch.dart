import '../api/domain/entities/preferences.dart';
import '../core/kits/data_kit.dart';

abstract final class CategorySwitch {
  static const String operation = 'CATEGORY_PREFERENCE_ERROR';

  static ServiceFailure rejected(final String code) =>
      ServiceFailure(type: FailureType.server, operation: operation, errorCode: Some(code));

  static Either<ServiceFailure, CategoryPreferenceEntity> find(
    final List<CategoryPreferenceEntity> categories,
    final String key,
  ) => Option.fromNullable(
    categories.where((final CategoryPreferenceEntity item) => item.key == key).firstOrNull,
  ).toEither(() => rejected(ServiceErrorCodes.categoryUnknown));

  static Either<ServiceFailure, CategoryPreferenceEntity> applied(
    final UpdatedPreferencesEntity updated,
    final String key,
  ) => Option.fromNullable(
    updated.rejected.where((final RejectedChoiceEntity item) => item.key == key).firstOrNull,
  ).match(() => find(updated.categories, key), (final RejectedChoiceEntity item) => Left(rejected(item.error)));

  static Option<CategoryChoiceEntity> flip(final CategoryPreferenceEntity current) =>
      current.locked ? const None() : Some(CategoryChoiceEntity(key: current.key, enabled: !current.enabled));
}
