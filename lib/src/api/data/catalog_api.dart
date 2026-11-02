import '../../core/kits/data_kit.dart';
import '../client/api_http_client.dart';
import '../domain/entities/catalog.dart';
import 'models/catalog.dart';

final class CatalogApi {
  const CatalogApi({required this.http, required this.logger});

  final ApiHttpClient http;

  final KitLogger logger;

  Future<Either<ServiceFailure, List<CategoryEntity>>> listCategories() => RepositoryGuard.guard(logger, () async {
    final ApiResponse response = await http.send(const ApiRequest(HttpVerb.get, <String>['categories']));
    return response.list.map(CategoryModel.parse).toList(growable: false);
  }, 'LIST_CATEGORIES_ERROR');
}
