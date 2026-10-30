import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/src/setup/ios_setup.dart';

void main() {
  late Directory app;
  late List<List<String>> calls;
  late List<String> scripts;

  IosSetup setup({final int exitCode = 0, final String stdout = 'Added', final String stderr = ''}) => IosSetup(
    appRoot: app,
    run: (final String executable, final List<String> arguments) async {
      calls.add(<String>[executable, ...arguments]);
      scripts.add(File(arguments.first).readAsStringSync());
      return ProcessResult(0, exitCode, stdout, stderr);
    },
  );

  void createXcodeProject() {
    File('${app.path}/ios/Runner.xcodeproj/project.pbxproj').createSync(recursive: true);
  }

  File extensionFile(final String name) => File('${app.path}/ios/NotificationService/$name');

  setUp(() {
    app = Directory.systemTemp.createTempSync('nk_app');
    calls = <List<String>>[];
    scripts = <String>[];
  });

  tearDown(() => app.deleteSync(recursive: true));

  test('fails outside a Flutter app and writes nothing', () async {
    final result = await setup().setUp();

    expect(result.succeeded, isFalse);
    expect(result.message, IosSetup.missingProject);
    expect(calls, isEmpty);
    expect(Directory('${app.path}/ios/NotificationService').existsSync(), isFalse);
  });

  test('writes the extension sources and registers the target with xcodeproj', () async {
    createXcodeProject();

    final result = await setup().setUp();

    expect(result.succeeded, isTrue);
    expect(result.message, 'Added\n${IosSetup.missingGoogleService}');
    expect(extensionFile('NotificationService.swift').readAsStringSync(), startsWith('import UserNotifications'));
    expect(extensionFile('Info.plist').readAsStringSync(), startsWith('<?xml'));
    expect(extensionFile('NotificationService.xcconfig').readAsStringSync(), contains('Generated.xcconfig'));
    expect(calls.single.first, 'ruby');
    expect(calls.single.last, '${app.path}/ios/Runner.xcodeproj');
    expect(scripts.single, contains("require 'xcodeproj'"));
    expect(File(calls.single[1]).existsSync(), isFalse);
  });

  test('says nothing about Firebase when GoogleService-Info.plist is there', () async {
    createXcodeProject();
    File('${app.path}/ios/Runner/GoogleService-Info.plist').createSync(recursive: true);

    expect((await setup().setUp()).message, 'Added');
  });

  test('the script also turns on Push Notifications and Background Modes', () async {
    createXcodeProject();

    await setup().setUp();

    expect(scripts.single, contains("'aps-environment'"));
    expect(scripts.single, contains("'remote-notification'"));
  });

  test('keeps sources the app already customized', () async {
    createXcodeProject();
    extensionFile('NotificationService.swift')
      ..createSync(recursive: true)
      ..writeAsStringSync('custom');

    await setup().setUp();

    expect(extensionFile('NotificationService.swift').readAsStringSync(), 'custom');
  });

  test('explains how to install xcodeproj when the gem is missing', () async {
    createXcodeProject();

    final result = await setup(exitCode: 1, stderr: 'cannot load such file -- xcodeproj (LoadError)').setUp();

    expect(result.succeeded, isFalse);
    expect(result.message, contains('gem install xcodeproj'));
  });

  test('reports other xcodeproj errors as they are', () async {
    createXcodeProject();

    final result = await setup(exitCode: 1, stderr: 'Runner target not found.').setUp();

    expect(result.succeeded, isFalse);
    expect(result.message, 'Runner target not found.');
  });
}
