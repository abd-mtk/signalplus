import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../api/client/api_config.dart';
import '../api/domain/entities/enums.dart';
import '../core/kits/domain_kit.dart';
import '../core/utils/logger.dart';
import '../push/models/push_config.dart';
import '../push/models/push_settings.dart';

final class SignalPlusConfig {
  const SignalPlusConfig({
    required this.appId,
    this.locale = const None(),
    this.push = const PushConfig(),
    this.baseUrl = ApiConfig.defaultBaseUrl,
    this.timeout = const Duration(seconds: 20),
    this.registerOnStart = true,
    this.firebaseOptions = const None(),
    this.logger = const None(),
  });

  final String appId;

  /// The app's language; without it, the device's.
  final Option<ServiceLocale> locale;

  final PushConfig push;

  final String baseUrl;

  final Duration timeout;

  final bool registerOnStart;

  final Option<FirebaseOptions> firebaseOptions;

  final Option<LogSink> logger;

  ServiceLocale get language => locale.getOrElse(deviceLanguage);

  ApiConfig get api => ApiConfig(appId: appId, locale: language, baseUrl: baseUrl, timeout: timeout);

  KitLogger get log => KitLogger.of(logger).tagged('SignalPlus');

  PushSettings settings({required final String appName}) =>
      PushSettings(appName: appName, locale: language, options: push, logger: logger);

  static ServiceLocale deviceLanguage() =>
      WidgetsFlutterBinding.ensureInitialized().platformDispatcher.locale.languageCode == ServiceLocale.ar.wire
          ? ServiceLocale.ar
          : ServiceLocale.en;
}
