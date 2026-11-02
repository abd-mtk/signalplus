import '../../../core/kits/data_kit.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/enums.dart';

abstract final class CategoryModel {
  static CategoryEntity parse(final Object? item) {
    final JsonMap json = JsonReader.object(item, 'Category');
    return CategoryEntity(
      key: JsonReader.string(json, 'Key'),
      name: JsonReader.string(json, 'Name'),
      description: JsonReader.optString(json, 'Description'),
      lane: Lane.parse(JsonReader.string(json, 'Lane')),
      locked: JsonReader.boolean(json, 'Locked'),
      defaultEnabled: JsonReader.boolean(json, 'DefaultEnabled'),
    );
  }
}
