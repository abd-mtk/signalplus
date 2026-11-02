import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;

import '../core/utils/logger.dart';
import 'client/api_config.dart';
import 'client/api_http_client.dart';
import 'data/catalog_api.dart';
import 'data/installations_api.dart';
import 'data/notifications_api.dart';
import 'data/preferences_api.dart';
import 'data/topics_api.dart';
import 'domain/entities/enums.dart';

final class SignalPlusClient {
  SignalPlusClient({required this.api, required this.logger, required this.ownsClient})
    : installations = InstallationsApi(http: api, logger: logger),
      preferences = PreferencesApi(http: api, logger: logger),
      topics = TopicsApi(http: api, logger: logger),
      catalog = CatalogApi(http: api, logger: logger),
      notifications = NotificationsApi(http: api, logger: logger);

  factory SignalPlusClient.create(
    final ApiConfig config, {
    final Option<http.Client> client = const None(),
    final KitLogger logger = const KitLogger(sink: KitLogger.silentSink, tag: 'SignalPlus'),
  }) => SignalPlusClient(
    api: ApiHttpClient(config: config, client: client.getOrElse(http.Client.new)),
    logger: logger,
    ownsClient: client.isNone(),
  );

  final ApiHttpClient api;

  final KitLogger logger;

  final bool ownsClient;

  final InstallationsApi installations;

  final PreferencesApi preferences;

  final TopicsApi topics;

  final CatalogApi catalog;

  final NotificationsApi notifications;

  void close() {
    if (ownsClient) api.client.close();
  }

  void useLocale(final ServiceLocale locale) => api.locale = locale;
}
