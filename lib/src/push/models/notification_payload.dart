import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../messages/extensions.dart';
import '../messages/message_keys.dart';
import 'notification_link.dart';

final class NotificationPayload extends Equatable {
  const NotificationPayload({
    required this.title,
    required this.body,
    required this.data,
    this.rawPayload = const None(),
  });

  factory NotificationPayload.fromMap(
    final Map<String, dynamic> map, {
    final String defaultTitle = '',
    final String defaultBody = '',
  }) => NotificationPayload(
    title: map.nonEmptyTextAt(MessageKeys.title).getOrElse(() => defaultTitle),
    body: map.nonEmptyTextAt(MessageKeys.body).getOrElse(() => defaultBody),
    data: map,
  );

  final String title;

  final String body;

  final Map<String, dynamic> data;

  final Option<String> rawPayload;

  Option<String> get notifyId => data.nonEmptyTextAt(MessageKeys.notifyId);

  Option<String> get category => data.nonEmptyTextAt(MessageKeys.category);

  Option<Uri> get link => data.nonEmptyTextAt(MessageKeys.link).flatMap(NotificationLink.parse);

  @override
  List<Object> get props => <Object>[title, body, data, rawPayload];
}
