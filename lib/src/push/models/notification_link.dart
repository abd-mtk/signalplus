import 'package:fpdart/fpdart.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class NotificationLink {
  static const int maxLength = 2048;

  static const Set<String> forbidden = <String>{
    'http',
    'javascript',
    'vbscript',
    'data',
    'file',
    'content',
    'intent',
    'blob',
    'about',
  };

  static Option<Uri> parse(final String text) {
    final String value = text.trim();
    if (value.isEmpty || value.length > maxLength || value.contains(' ')) return const None();
    return Option.fromNullable(Uri.tryParse(value)).filter((final Uri uri) {
      final String scheme = uri.scheme.toLowerCase();
      if (scheme.isEmpty || forbidden.contains(scheme)) return false;
      return scheme != 'https' || uri.host.isNotEmpty;
    });
  }

  static bool isWeb(final Uri uri) => uri.scheme.toLowerCase() == 'https';

  static Future<bool> open(final Uri uri) =>
      launchUrl(uri, mode: isWeb(uri) ? LaunchMode.inAppBrowserView : LaunchMode.platformDefault);
}
