import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/api/client/api_config.dart';
import 'package:signalplus/src/api/domain/entities/device_auth.dart';
import 'package:signalplus/src/api/signalplus_client.dart';

Object? fixture(final String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

Map<String, dynamic> envelope(final Object? data, {final int code = 1, final List<String> errors = const <String>[]}) =>
    <String, dynamic>{
      'Code': code,
      'Message': code == 1 ? 'تمت العملية' : 'فشلت العملية',
      'Data': data,
      'Error': errors,
    };

final class StubResponse {
  const StubResponse(this.status, {this.body = const None(), this.headers = const <String, String>{}});

  StubResponse.data(
    final Object? data, {
    final int status = 200,
    final Map<String, String> headers = const <String, String>{},
  }) : this(status, body: Some(envelope(data)), headers: headers);

  StubResponse.failure(
    final int status,
    final List<String> errors, {
    final Object? data,
    final String message = 'فشلت العملية',
  }) : this(status, body: Some(<String, dynamic>{'Code': 0, 'Message': message, 'Data': data, 'Error': errors}));

  final int status;

  final Option<Object> body;

  final Map<String, String> headers;
}

final class RecordedRequest {
  const RecordedRequest(this.method, this.url, this.headers, this.body);

  final String method;

  final Uri url;

  final Map<String, String> headers;

  final String body;

  Object? get json => body.isEmpty ? null : jsonDecode(body);

  String get route => '$method ${url.path}';
}

final class ApiHarness {
  ApiHarness({this.config = defaultConfig}) {
    client = SignalPlusClient.create(config, client: Some(MockClient(handle)));
  }

  static const String appId = 'sdk_01J9TEST';

  static const ApiConfig defaultConfig = ApiConfig(appId: appId, locale: ServiceLocale.ar, baseUrl: 'https://sdk.test');

  static const DeviceAuth device = DeviceAuth(installationId: 'i-1');

  final ApiConfig config;

  late final SignalPlusClient client;

  final List<RecordedRequest> requests = <RecordedRequest>[];

  final Map<String, StubResponse> routes = <String, StubResponse>{};

  final Map<String, List<StubResponse>> sequences = <String, List<StubResponse>>{};

  Object? thrown;

  void on(final String route, final StubResponse response) => routes[route] = response;

  void onSequence(final String route, final List<StubResponse> responses) =>
      sequences[route] = <StubResponse>[...responses];

  RecordedRequest get last => requests.last;

  List<String> get routesCalled => requests.map((final RecordedRequest request) => request.route).toList();

  Future<http.Response> handle(final http.Request request) async {
    final RecordedRequest recorded = RecordedRequest(request.method, request.url, request.headers, request.body);
    requests.add(recorded);
    if (thrown case final Object error) throw error;
    final List<StubResponse> queued = sequences[recorded.route] ?? <StubResponse>[];
    final StubResponse stub = queued.isNotEmpty
        ? queued.removeAt(0)
        : routes[recorded.route] ?? const StubResponse(404);
    return http.Response.bytes(
      stub.body.match(() => <int>[], (final Object body) => utf8.encode(jsonEncode(body))),
      stub.status,
      headers: <String, String>{'content-type': 'application/json; charset=utf-8', ...stub.headers},
    );
  }
}

T rightOf<T>(final Either<ServiceFailure, T> result) => result.match(
  (final ServiceFailure failure) => throw StateError('Expected Right, got $failure'),
  (final T value) => value,
);

ServiceFailure leftOf<T>(final Either<ServiceFailure, T> result) => result.match(
  (final ServiceFailure failure) => failure,
  (final T value) => throw StateError('Expected Left, got $value'),
);
