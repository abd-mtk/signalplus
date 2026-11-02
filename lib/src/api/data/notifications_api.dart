import '../../core/kits/data_kit.dart';
import '../client/api_http_client.dart';
import '../domain/entities/notification.dart';
import 'models/notification.dart';

final class NotificationsApi {
  const NotificationsApi({required this.http, required this.logger});

  final ApiHttpClient http;

  final KitLogger logger;

  Future<Either<ServiceFailure, bool>> reportEvent(
    final DeviceAuth device,
    final String notificationId,
    final DeliveryEventEntity event,
  ) => RepositoryGuard.guard(logger, () async {
    final ApiResponse response = await http.send(
      ApiRequest.device(HttpVerb.post, device, <String>[
        'notifications',
        notificationId,
        'events',
      ], body: Some(DeliveryEventModel.toJson(event))),
    );
    return JsonReader.boolean(response.object, 'Applied');
  }, 'REPORT_EVENT_ERROR');
}
