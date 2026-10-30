import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/src/setup/android_setup.dart';

const String kotlinTemplate = '''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
    }
}

flutter {
    source = "../.."
}
''';

const String groovyTemplate = '''
android {
    compileSdkVersion 33

    defaultConfig {
        minSdkVersion 21
    }
}

dependencies {
    implementation 'androidx.core:core:1.9.0'
}
''';

void main() {
  group('GradleEdit', () {
    test('the Flutter kts template gets the flag and the library', () {
      final GradleEdit edit = GradleEdit.apply(kotlinTemplate, kotlin: true);

      expect(edit.changed, isTrue);
      expect(
        edit.source,
        contains('    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n        sourceCompatibility'),
      );
      expect(edit.source, endsWith('dependencies {\n    coreLibraryDesugaring("${AndroidSetup.desugarLibrary}")\n}\n'));
      expect(edit.source, contains('compileSdk = flutter.compileSdkVersion'));
    });

    test('running it again changes nothing', () {
      final GradleEdit first = GradleEdit.apply(kotlinTemplate, kotlin: true);
      final GradleEdit second = GradleEdit.apply(first.source, kotlin: true);

      expect(second.changed, isFalse);
      expect(second.notes, <String>['Gradle: already set up.']);
    });

    test('groovy gets its own syntax, an existing dependencies block, and raised sdk levels', () {
      final GradleEdit edit = GradleEdit.apply(groovyTemplate, kotlin: false);

      expect(
        edit.source,
        contains('android {\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n    }'),
      );
      expect(edit.source, contains("dependencies {\n    coreLibraryDesugaring '${AndroidSetup.desugarLibrary}'"));
      expect(edit.source, contains('compileSdkVersion 35'));
      expect(edit.source, contains('minSdkVersion 24'));
      expect(edit.notes, containsAll(<String>['compileSdk: raised from 33 to 35.', 'minSdk: raised from 21 to 24.']));
    });

    test('a flag set to false is switched on, not added twice', () {
      final GradleEdit edit = GradleEdit.apply(
        kotlinTemplate.replaceFirst(
          'compileOptions {',
          'compileOptions {\n        isCoreLibraryDesugaringEnabled = false',
        ),
        kotlin: true,
      );

      expect(RegExp('isCoreLibraryDesugaringEnabled').allMatches(edit.source), hasLength(1));
      expect(edit.source, contains('isCoreLibraryDesugaringEnabled = true'));
    });

    test('a file it cannot read is left to the developer', () {
      final GradleEdit edit = GradleEdit.apply('// empty', kotlin: true);

      expect(edit.notes.first, contains('yourself'));
    });
  });

  group('AndroidSetup', () {
    late Directory app;

    setUp(() => app = Directory.systemTemp.createTempSync('sp_android'));

    tearDown(() => app.deleteSync(recursive: true));

    test('skips an app without Android', () {
      expect(AndroidSetup(appRoot: app).setUp(), <String>[AndroidSetup.missingBuildFile]);
    });

    test('writes the build file and asks for google-services.json when it is missing', () {
      final File build =
          File('${app.path}/android/app/build.gradle.kts')
            ..createSync(recursive: true)
            ..writeAsStringSync(kotlinTemplate);

      final List<String> notes = AndroidSetup(appRoot: app).setUp();

      expect(build.readAsStringSync(), contains('isCoreLibraryDesugaringEnabled = true'));
      expect(notes.last, AndroidSetup.missingGoogleServices);
    });
  });
}
