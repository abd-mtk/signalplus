import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/kits/data_kit.dart';
import '../domain/entities/device_auth.dart';
import '../domain/entities/enums.dart';
import 'api_config.dart';

export '../domain/entities/device_auth.dart';

enum HttpVerb { get, put, post, patch, delete }

final class ApiRequest {
  const ApiRequest(this.verb, this.segments, {this.body = const None()});

  ApiRequest.device(
    final HttpVerb verb,
    final DeviceAuth device,
    final List<String> segments, {
    final Option<Object> body = const None(),
  }) : this(verb, <String>['installations', device.installationId, ...segments], body: body);

  final HttpVerb verb;

  final List<String> segments;

  final Option<Object> body;
}

final class ApiResponse {
  const ApiResponse(this.data);

  final Option<Object> data;

  JsonMap get object => JsonReader.object(data.toNullable(), 'Data');

  List<dynamic> get list => switch (data.toNullable()) {
    final List<dynamic> items => items,
    _ => throw const DecodeException('Data is not a list'),
  };
}

final class ApiHttpClient {
  ApiHttpClient({required this.config, required this.client}) : locale = config.locale;

  static const List<String> root = <String>['sdk', 'v1'];
  static const String appIdHeader = 'X-SignalPlus-App-Id';

  final ApiConfig config;

  final http.Client client;

  ServiceLocale locale;

  Future<ApiResponse> send(final ApiRequest request) async {
    final Uri uri = uriFor(request);
    final http.Request outgoing = http.Request(request.verb.name.toUpperCase(), uri)
      ..headers.addAll(headersFor(request));
    request.body.match(() {}, (final Object body) => outgoing.body = jsonEncode(body));
    try {
      return decode(await client.send(outgoing).then(http.Response.fromStream).timeout(config.timeout));
    } on TimeoutException {
      throw NetworkException('${request.verb.name.toUpperCase()} ${uri.path} timed out', timedOut: true);
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    }
  }

  Uri uriFor(final ApiRequest request) {
    final Uri base = Uri.parse(config.baseUrl);
    return base.replace(
      pathSegments: <String>[
        ...base.pathSegments.where((final String part) => part.isNotEmpty),
        ...root,
        ...request.segments,
      ],
    );
  }

  Map<String, String> headersFor(final ApiRequest request) => <String, String>{
    'Accept': 'application/json',
    'Accept-Language': locale.wire,
    appIdHeader: config.appId,
    if (request.body.isSome()) 'Content-Type': 'application/json',
  };

  static ApiResponse decode(final http.Response response) {
    final Option<Object> body = parseBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ServiceException(statusCode: response.statusCode, body: body.toNullable());
    }
    return ApiResponse(
      body.flatMap((final Object value) => value is Map ? Option<Object>.fromNullable(value['Data']) : const None()),
    );
  }

  static Option<Object> parseBody(final http.Response response) {
    if (response.bodyBytes.isEmpty) return const None();
    try {
      return Option<Object>.fromNullable(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw DecodeException('Response ${response.statusCode} is not JSON');
      }
      return some(response.body);
    }
  }
}
