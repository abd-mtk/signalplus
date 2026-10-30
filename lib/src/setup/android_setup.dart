import 'dart:io';

/// Brings `android/app/build.gradle(.kts)` up to what the package needs, touching only what is missing.
final class AndroidSetup {
  const AndroidSetup({required this.appRoot});

  static const String desugarLibrary = 'com.android.tools:desugar_jdk_libs:2.1.5';

  static const int minCompileSdk = 35;

  static const int minSdk = 24;

  static const String missingBuildFile = 'android/app/build.gradle(.kts) not found, skipped.';

  static const String missingGoogleServices =
      'android/app/google-services.json not found: run flutterfire configure (or pass firebaseOptions to init).';

  final Directory appRoot;

  List<String> setUp() {
    final List<File> candidates = <File>[
      File('${appRoot.path}/android/app/build.gradle.kts'),
      File('${appRoot.path}/android/app/build.gradle'),
    ];
    final File? build = candidates.where((final File file) => file.existsSync()).firstOrNull;
    if (build == null) return const <String>[missingBuildFile];

    final GradleEdit edit = GradleEdit.apply(build.readAsStringSync(), kotlin: build.path.endsWith('.kts'));
    if (edit.changed) build.writeAsStringSync(edit.source);
    return <String>[
      ...edit.notes,
      if (!File('${appRoot.path}/android/app/google-services.json').existsSync()) missingGoogleServices,
    ];
  }
}

final class GradleEdit {
  const GradleEdit(this.source, this.notes, {required this.changed});

  factory GradleEdit.apply(final String original, {required final bool kotlin}) {
    final List<String> notes = <String>[];
    String source = original;

    final String flag = kotlin ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
    final RegExp disabled = RegExp(r'(oreLibraryDesugaringEnabled\s*=?\s*)false');
    if (disabled.hasMatch(source)) {
      source = source.replaceFirstMapped(disabled, (final Match match) => '${match[1]}true');
      notes.add('Core library desugaring: turned on.');
    } else if (!RegExp(r'oreLibraryDesugaringEnabled\s*=?\s*true').hasMatch(source)) {
      final Match? options = RegExp(r'^([ \t]*)compileOptions\s*\{[ \t]*$', multiLine: true).firstMatch(source);
      final Match? android = RegExp(r'^([ \t]*)android\s*\{[ \t]*$', multiLine: true).firstMatch(source);
      if (options != null) {
        source = source.replaceRange(options.end, options.end, '\n${options[1]}    $flag');
        notes.add('Core library desugaring: turned on.');
      } else if (android != null) {
        final String indent = '${android[1]}    ';
        source = source.replaceRange(
          android.end,
          android.end,
          '\n${indent}compileOptions {\n$indent    $flag\n$indent}',
        );
        notes.add('Core library desugaring: turned on.');
      } else {
        notes.add('Core library desugaring: add `$flag` to android.compileOptions yourself.');
      }
    }

    if (!RegExp('coreLibraryDesugaring\\s*[("\']').hasMatch(source)) {
      final String dependency = kotlin ? 'coreLibraryDesugaring("$desugar")' : "coreLibraryDesugaring '$desugar'";
      final Match? block = RegExp(r'^dependencies\s*\{[ \t]*$', multiLine: true).firstMatch(source);
      source =
          block != null
              ? source.replaceRange(block.end, block.end, '\n    $dependency')
              : '${source.trimRight()}\n\ndependencies {\n    $dependency\n}\n';
      notes.add('Desugaring library: added $desugar.');
    }

    source = raise(
      source,
      RegExp(r'(compileSdk(?:Version)?\s*=?\s*)(\d+)'),
      AndroidSetup.minCompileSdk,
      'compileSdk',
      notes,
    );
    source = raise(source, RegExp(r'(minSdk(?:Version)?\s*=?\s*)(\d+)'), AndroidSetup.minSdk, 'minSdk', notes);

    final bool changed = source != original;
    if (!changed) notes.add('Gradle: already set up.');
    return GradleEdit(source, notes, changed: changed);
  }

  static const String desugar = AndroidSetup.desugarLibrary;

  final String source;

  final List<String> notes;

  final bool changed;

  static String raise(
    final String source,
    final RegExp pattern,
    final int minimum,
    final String name,
    final List<String> notes,
  ) => source.replaceAllMapped(pattern, (final Match match) {
    final int value = int.parse(match[2]!);
    if (value >= minimum) return match[0]!;
    notes.add('$name: raised from $value to $minimum.');
    return '${match[1]}$minimum';
  });
}
