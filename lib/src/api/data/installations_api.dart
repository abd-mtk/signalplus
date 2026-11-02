import '../../core/kits/data_kit.dart';
import '../client/api_http_client.dart';
import '../domain/entities/installation.dart';
import 'models/installation.dart';

final class InstallationsApi {
  const InstallationsApi({required this.http, required this.logger});

  final ApiHttpClient http;

  final KitLogger logger;

  Future<Either<ServiceFailure, SdkInstallationEntity>> register(
    final DeviceAuth device,
    final RegisterInstallationEntity request,
  ) => installation(
    ApiRequest.device(HttpVerb.put, device, const <String>[], body: Some(InstallationModel.toJson(request))),
    'REGISTER_INSTALLATION_ERROR',
  );

  Future<Either<ServiceFailure, SdkInstallationEntity>> login(
    final DeviceAuth device, {
    required final String externalId,
  }) => installation(
    ApiRequest.device(HttpVerb.post, device, const <String>[
      'login',
    ], body: Some(InstallationModel.loginToJson(externalId))),
    'LOGIN_ERROR',
  );

  Future<Either<ServiceFailure, SdkInstallationEntity>> logout(final DeviceAuth device) =>
      installation(ApiRequest.device(HttpVerb.post, device, const <String>['logout']), 'LOGOUT_ERROR');

  Future<Either<ServiceFailure, SdkInstallationEntity>> installation(
    final ApiRequest request,
    final String operation,
  ) => RepositoryGuard.guard(
    logger,
    () async => InstallationModel.installationFromJson((await http.send(request)).object),
    operation,
  );
}
