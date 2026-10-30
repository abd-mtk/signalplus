import 'package:flutter/material.dart';
import 'package:signalplus/signalplus.dart';

const String appId = String.fromEnvironment('SIGNALPLUS_APP_ID');
const String externalId = String.fromEnvironment('SIGNALPLUS_EXTERNAL_ID', defaultValue: 'demo-user');

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> onBackground(final RemoteMessage message) async => debugPrint('Background message ${message.messageId}');

void openFromNotification(final NotificationPayload payload) {
  debugPrint('Opened ${payload.title} (${payload.notifyId.getOrElse(() => 'no NotifyId')})');
  final Object? route = payload.data['route'];
  Option.fromNullable(navigatorKey.currentState).match(() {}, (final NavigatorState navigator) {
    if (route is String) navigator.pushNamed(route);
  });
}

Future<void> main() async {
  final Either<ServiceFailure, Unit> ready = await SignalPlus.init(
    const SignalPlusConfig(appId: appId, push: PushConfig(requestPermissionOnStartup: false)),
  );
  ready.match((final ServiceFailure failure) => debugPrint('SignalPlus is off: $failure'), (final Unit _) {});

  SignalPlus.onMessage((final RemoteMessage message) => debugPrint('Foreground ${message.messageId}'));
  SignalPlus.onNotificationTap(openFromNotification);
  await SignalPlus.onBackgroundMessage(onBackground);

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(final BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'Notification Kit Demo',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
    home: const DemoScreen(),
  );
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => DemoScreenState();
}

class DemoScreenState extends State<DemoScreen> {
  final List<String> lines = <String>[];

  void log<T>(final String action, final Either<ServiceFailure, T> result) {
    final String line = result.match(
      (final ServiceFailure failure) =>
          '✗ $action: ${failure.errorCode.getOrElse(() => failure.type.code)} ${failure.message}',
      (final T value) => '✓ $action: $value',
    );
    if (mounted) setState(() => lines.insert(0, line));
  }

  @override
  Widget build(final BuildContext context) {
    final List<(String, Future<void> Function())> actions = <(String, Future<void> Function())>[
      ('Permission', () async => log('permission', await SignalPlus.requestPermission())),
      (
        'English',
        () async => log(
          'locale',
          (await SignalPlus.setLocale(ServiceLocale.en)).map((final SdkInstallationEntity item) => item.installationId),
        ),
      ),
      (
        'Login',
        () async => log(
          'login',
          (await SignalPlus.login(externalId)).map((final SdkInstallationEntity item) => item.externalId),
        ),
      ),
      (
        'Categories → channels',
        () async =>
            log('categories', (await SignalPlus.categories()).map((final List<CategoryEntity> items) => items.length)),
      ),
      (
        'Preferences',
        () async => log(
          'preferences',
          (await SignalPlus.preferences()).map((final PreferencesEntity value) => value.categories.length),
        ),
      ),
      ('My topics', () async => log('topics', await SignalPlus.recipientTopics())),
      ('Logout', () async => log('logout', await SignalPlus.logout())),
      ('Clear', () async => log('clear', await SignalPlus.clearNotifications())),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('SignalPlus Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (appId.isEmpty) const Text('Run with --dart-define=SIGNALPLUS_APP_ID=sdk_… (Environment → App SDK).'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (String label, Future<void> Function() run) in actions)
                OutlinedButton(onPressed: run, child: Text(label)),
            ],
          ),
          const SizedBox(height: 16),
          for (final String line in lines) Text(line, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
