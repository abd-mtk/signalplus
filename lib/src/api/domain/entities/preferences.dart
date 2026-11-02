import '../../../core/kits/domain_kit.dart';
import 'enums.dart';

final class CategoryPreferenceEntity extends Equatable {
  const CategoryPreferenceEntity({
    required this.key,
    required this.name,
    required this.enabled,
    required this.locked,
    this.description = const None(),
  });

  final String key;

  final String name;

  final Option<String> description;

  final bool enabled;

  final bool locked;

  @override
  List<Object> get props => <Object>[key, name, description, enabled, locked];
}

final class QuietHoursEntity extends Equatable {
  const QuietHoursEntity({required this.start, required this.end, required this.days});

  final String start;

  final String end;

  final List<WeekDay> days;

  @override
  List<Object> get props => <Object>[start, end, days];
}

final class PreferencesEntity extends Equatable {
  const PreferencesEntity({required this.categories, this.quietHours = const None(), this.muted = false});

  final List<CategoryPreferenceEntity> categories;

  final Option<QuietHoursEntity> quietHours;

  final bool muted;

  @override
  List<Object> get props => <Object>[categories, quietHours, muted];
}

final class RejectedChoiceEntity extends Equatable {
  const RejectedChoiceEntity({required this.key, required this.error});

  final String key;

  final String error;

  @override
  List<Object> get props => <Object>[key, error];
}

final class UpdatedPreferencesEntity extends Equatable {
  const UpdatedPreferencesEntity({
    required this.categories,
    required this.rejected,
    this.quietHours = const None(),
    this.muted = false,
  });

  final List<CategoryPreferenceEntity> categories;

  final Option<QuietHoursEntity> quietHours;

  final bool muted;

  final List<RejectedChoiceEntity> rejected;

  @override
  List<Object> get props => <Object>[categories, quietHours, muted, rejected];
}

final class CategoryChoiceEntity extends Equatable {
  const CategoryChoiceEntity({required this.key, required this.enabled});

  final String key;

  final bool enabled;

  @override
  List<Object> get props => <Object>[key, enabled];
}
