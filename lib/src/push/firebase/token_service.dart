import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/errors/exceptions.dart';
import '../../core/utils/logger.dart';
import '../messages/extensions.dart';
import '../models/push_events.dart';

final class TokenService {
  TokenService({
    required this.messaging,
    required this.events,
    required final KitLogger logger,
    this.apnsAttempts = 5,
    this.apnsRetryDelay = const Duration(seconds: 1),
    this.registerTimeout = const Duration(seconds: 30),
  }) : log = logger.tagged('TokenService');

  static const String apnsNotReady = 'APNS_TOKEN_NOT_READY';
  static const String tokenUnavailable = 'FCM_TOKEN_UNAVAILABLE';

  final FirebaseMessaging messaging;

  final PushEvents events;

  final KitLogger log;

  final int apnsAttempts;

  final Duration apnsRetryDelay;

  final Duration registerTimeout;

  Option<StreamSubscription<String>> refreshSubscription = const None();

  void listenForRefresh() {
    refreshSubscription = refreshSubscription.alt(
      () => some(
        messaging.onRegistered.listen(
          publish,
          onError:
              (final Object error, final StackTrace stackTrace) =>
                  log.error('Registration stream failed', error, stackTrace),
        ),
      ),
    );
  }

  Future<String> getToken() async {
    if (!await apnsReady()) throw const PushException(apnsNotReady);
    final Future<String> registered = messaging.onRegistered.first.timeout(
      registerTimeout,
      onTimeout: () => throw const PushException(tokenUnavailable),
    );
    try {
      await messaging.register();
    } on Object {
      registered.ignore();
      rethrow;
    }
    final String token = await registered;
    publish(token);
    return token;
  }

  Future<Option<String>> refresh() async {
    try {
      return some(await getToken());
    } on Object catch (error, stackTrace) {
      log.error('Failed to register with FCM', error, error is PushException ? StackTrace.empty : stackTrace);
      return const None();
    }
  }

  Future<void> deleteToken() async {
    await messaging.unregister();
    events.forgetToken();
  }

  Future<void> dispose() async {
    await refreshSubscription.match(
      () async {},
      (final StreamSubscription<String> subscription) => subscription.cancel(),
    );
    refreshSubscription = const None();
  }

  Future<bool> apnsReady() async {
    if (!defaultTargetPlatform.isApple) return true;
    for (int attempt = 1; attempt <= apnsAttempts; attempt++) {
      if (await messaging.hasApnsToken) return true;
      if (attempt < apnsAttempts) await Future<void>.delayed(apnsRetryDelay);
    }
    return false;
  }

  void publish(final String token) {
    if (events.latestToken == some(token)) return;
    log.info('Token: ${token.masked}');
    events.token(token);
  }
}
