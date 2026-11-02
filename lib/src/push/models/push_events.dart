import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fpdart/fpdart.dart';

import '../../api/domain/entities/enums.dart';
import 'notification_payload.dart';

final class PushEvents {
  final StreamController<String> tokenController = StreamController<String>.broadcast(sync: true);

  final StreamController<NotificationPayload> tapController = StreamController<NotificationPayload>.broadcast(
    sync: true,
  );

  final StreamController<RemoteMessage> messageController = StreamController<RemoteMessage>.broadcast(sync: true);

  final StreamController<PushPermission> permissionController = StreamController<PushPermission>.broadcast(sync: true);

  Option<String> latestToken = const None();

  Option<NotificationPayload> pendingTap = const None();

  Stream<String> get tokens => tokenController.stream;

  Stream<NotificationPayload> get taps => tapController.stream;

  Stream<RemoteMessage> get messages => messageController.stream;

  Stream<PushPermission> get permissions => permissionController.stream;

  void token(final String value) {
    latestToken = some(value);
    tokenController.add(value);
  }

  void forgetToken() => latestToken = const None();

  void tap(final NotificationPayload payload) {
    if (tapController.hasListener) return tapController.add(payload);
    pendingTap = pendingTap.alt(() => some(payload));
  }

  Option<NotificationPayload> takePendingTap() {
    final Option<NotificationPayload> taken = pendingTap;
    pendingTap = const None();
    return taken;
  }

  void message(final RemoteMessage value) => messageController.add(value);

  void permission(final PushPermission value) => permissionController.add(value);

  Future<void> close() async {
    await Future.wait(<Future<void>>[
      tokenController.close(),
      tapController.close(),
      messageController.close(),
      permissionController.close(),
    ]);
  }
}
