import '../../../core/kits/domain_kit.dart';
import 'enums.dart';

final class CategoryEntity extends Equatable {
  const CategoryEntity({
    required this.key,
    required this.name,
    required this.lane,
    required this.locked,
    required this.defaultEnabled,
    this.description = const None(),
  });

  final String key;

  final String name;

  final Option<String> description;

  final Lane lane;

  final bool locked;

  final bool defaultEnabled;

  String get channelId => key;

  @override
  List<Object> get props => <Object>[key, name, description, lane, locked, defaultEnabled];
}
