import '../../core/kits/data_kit.dart';
import '../client/api_http_client.dart';
import '../domain/entities/preferences.dart';
import 'models/preferences.dart';

final class PreferencesApi {
  const PreferencesApi({required this.http, required this.logger});

  static const List<String> preferences = <String>['recipient', 'preferences'];
  static const List<String> quietHours = <String>['recipient', 'quiet-hours'];
  static const List<String> mute = <String>['recipient', 'mute'];

  final ApiHttpClient http;

  final KitLogger logger;

  Future<Either<ServiceFailure, PreferencesEntity>> getPreferences(final DeviceAuth device) =>
      read(ApiRequest.device(HttpVerb.get, device, preferences), 'GET_PREFERENCES_ERROR');

  Future<Either<ServiceFailure, UpdatedPreferencesEntity>> updatePreferences(
    final DeviceAuth device,
    final List<CategoryChoiceEntity> choices,
  ) => RepositoryGuard.guard(logger, () async {
    final ApiResponse response = await http.send(
      ApiRequest.device(HttpVerb.put, device, preferences, body: Some(PreferencesModel.choicesToJson(choices))),
    );
    return PreferencesModel.updatedFromJson(response.object);
  }, 'UPDATE_PREFERENCES_ERROR');

  Future<Either<ServiceFailure, PreferencesEntity>> setQuietHours(
    final DeviceAuth device,
    final QuietHoursEntity quietHours,
  ) => read(
    ApiRequest.device(
      HttpVerb.put,
      device,
      PreferencesApi.quietHours,
      body: Some(PreferencesModel.quietHoursToJson(quietHours)),
    ),
    'SET_QUIET_HOURS_ERROR',
  );

  Future<Either<ServiceFailure, PreferencesEntity>> clearQuietHours(final DeviceAuth device) =>
      read(ApiRequest.device(HttpVerb.delete, device, quietHours), 'CLEAR_QUIET_HOURS_ERROR');

  Future<Either<ServiceFailure, PreferencesEntity>> muteAll(final DeviceAuth device) =>
      read(ApiRequest.device(HttpVerb.put, device, mute), 'MUTE_ERROR');

  Future<Either<ServiceFailure, PreferencesEntity>> unmuteAll(final DeviceAuth device) =>
      read(ApiRequest.device(HttpVerb.delete, device, mute), 'UNMUTE_ERROR');

  Future<Either<ServiceFailure, PreferencesEntity>> read(final ApiRequest request, final String operation) =>
      RepositoryGuard.guard(
        logger,
        () async => PreferencesModel.fromJson((await http.send(request)).object),
        operation,
      );
}
