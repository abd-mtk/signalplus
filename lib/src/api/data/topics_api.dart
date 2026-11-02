import '../../core/kits/data_kit.dart';
import '../client/api_http_client.dart';

final class TopicsApi {
  const TopicsApi({required this.http, required this.logger});

  final ApiHttpClient http;

  final KitLogger logger;

  Future<Either<ServiceFailure, List<String>>> availableTopics() =>
      topics(const ApiRequest(HttpVerb.get, <String>['topics']), 'LIST_TOPICS_ERROR');

  Future<Either<ServiceFailure, List<String>>> recipientTopics(final DeviceAuth device) =>
      topics(ApiRequest.device(HttpVerb.get, device, const <String>['recipient', 'topics']), 'GET_TOPICS_ERROR');

  Future<Either<ServiceFailure, List<String>>> subscribe(final DeviceAuth device, final String topic) =>
      topics(ApiRequest.device(HttpVerb.put, device, <String>['recipient', 'topics', topic]), 'SUBSCRIBE_TOPIC_ERROR');

  Future<Either<ServiceFailure, List<String>>> unsubscribe(final DeviceAuth device, final String topic) => topics(
    ApiRequest.device(HttpVerb.delete, device, <String>['recipient', 'topics', topic]),
    'UNSUBSCRIBE_TOPIC_ERROR',
  );

  Future<Either<ServiceFailure, List<String>>> topics(final ApiRequest request, final String operation) =>
      RepositoryGuard.guard(
        logger,
        () async => JsonReader.strings((await http.send(request)).object, 'Topics'),
        operation,
      );
}
