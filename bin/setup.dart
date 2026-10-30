import 'dart:io';

import 'package:signalplus/src/setup/android_setup.dart';
import 'package:signalplus/src/setup/ios_setup.dart';

/// `dart run signalplus:setup`, from the root of the app: everything the package needs that code cannot do at run time.
Future<void> main() async {
  final Directory app = Directory.current;
  if (!File('${app.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the root of your Flutter app.');
    exitCode = 1;
    return;
  }

  stdout.writeln('Android');
  for (final String line in AndroidSetup(appRoot: app).setUp()) {
    stdout.writeln('  $line');
  }

  final IosSetupResult ios = await IosSetup(appRoot: app).setUp();
  stdout.writeln('iOS');
  for (final String line in ios.message.split('\n')) {
    (ios.succeeded ? stdout : stderr).writeln('  $line');
  }
  if (!ios.succeeded && ios.message != IosSetup.missingProject) exitCode = 1;

  stdout.writeln('\nStill yours: upload the APNs key (.p8) in Firebase Console → Project settings → Cloud Messaging.');
}
