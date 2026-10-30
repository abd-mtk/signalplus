import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/api/signalplus_client.dart';
import 'package:signalplus/src/core/errors/exceptions.dart';
import 'package:signalplus/src/device/fresh_install.dart';
import 'package:signalplus/src/device/installation_id_store.dart';
import 'package:signalplus/src/push/models/push_settings.dart';
import 'package:signalplus/src/push/notification/notification_channel.dart';
import 'package:signalplus/src/signal_plus/background_entry.dart';
import 'package:signalplus/src/signal_plus/signal_plus_runtime.dart';
import 'package:signalplus/src/signal_plus/signal_plus_state.dart';

import 'support/api_harness.dart';
import 'support/device_fakes.dart';

void silent(final String tag, final String message) {}

const SignalPlusConfig config = SignalPlusConfig(
  appId: ApiHarness.appId,
  locale: Some(ServiceLocale.ar),
  registerOnStart: false,
  logger: Some(silent),
);

Map<String, dynamic> view(final String id, {final Object? externalId}) => <String, dynamic>{
  'InstallationId': id,
  'ExternalId': externalId,
  'TokenStatus': 'Valid',
  'PushPermission': 'Granted',
};

const String register1 = 'PUT /sdk/v1/installations/install-1';

const String categoriesRoute = 'GET /sdk/v1/categories';

void main() {
  late ApiHarness harness;
  late FakePushPort push;
  late MemoryStore secure;
  late MemoryStore local;
  late int ids;
  late List<StreamSubscription<Object>> listeners;

  InstallationIdStore idStore() => InstallationIdStore(store: secure, newId: Some(() => 'install-${++ids}'));

  void start() => SignalPlusState.attach(
    SignalPlusRuntime(
      config: config,
      settings: config.settings(appName: 'Shop'),
      push: push,
      client: harness.client,
      installationIds: idStore(),
      externalIds: ExternalIdStore(store: secure),
      device: const FixedDevice(),
    ),
  );

  List<String> routes() => harness.routesCalled;

  bool noSecretSent() => harness.requests.every(
    (final RecordedRequest request) => !request.headers.containsKey('X-SignalPlus-Installation-Secret'),
  );

  Map<String, dynamic> body(final int index) => harness.requests[index].json! as Map<String, dynamic>;

  void registered() {
    secure.values[InstallationIdStore.key] = 'install-1';
  }

  setUp(() async {
    harness = ApiHarness();
    harness.on(register1, StubResponse.data(view('install-1'), status: 201));
    push = FakePushPort();
    secure = MemoryStore();
    local = MemoryStore()..values[FreshInstall.markerKey] = '1';
    ids = 0;
    listeners = <StreamSubscription<Object>>[];
    await SignalPlusState.reset(secureStore: secure, localStore: local);
    SignalPlusState.launchScheduler = (final void Function() run) => run();
    SignalPlusState.startPush = (final SignalPlusConfig _, final PushSettings _) async => push;
    SignalPlusState.createClient = (final SignalPlusConfig _) => harness.client;
    SignalPlusState.createDevice = (final SignalPlusConfig _) => const FixedDevice();
    SignalPlusState.installationIds = idStore();
  });

  tearDown(() async {
    await Future.wait(listeners.map((final StreamSubscription<Object> listener) => listener.cancel()));
    await SignalPlus.dispose();
  });

  group('init', () {
    test('starts the push side once, saves the display config and attaches', () async {
      int starts = 0;
      SignalPlusState.startPush = (final SignalPlusConfig _, final PushSettings _) async {
        starts++;
        return push;
      };

      final List<Either<ServiceFailure, Unit>> results = await Future.wait(<Future<Either<ServiceFailure, Unit>>>[
        SignalPlus.init(config),
        SignalPlus.init(config),
      ]);
      await SignalPlus.init(config);

      expect(results.every((final Either<ServiceFailure, Unit> result) => result.isRight()), isTrue);
      expect(starts, 1);
      expect(SignalPlus.isInitialized, isTrue);
      expect(secure.values[BackgroundSettings.configKey], contains('"AppName":"Shop"'));
      expect(secure.values[BackgroundSettings.configKey], contains('"Locale":"ar"'));
      expect(routes().where((final String route) => route != categoriesRoute), isEmpty);
    });

    test('on Android init creates one channel per category by itself', () async {
      harness.on(categoriesRoute, StubResponse.data(fixture('categories')));

      await SignalPlus.init(config);
      await pumpEventQueue();

      expect(routes(), <String>[categoriesRoute]);
      expect(push.channels.map((final ChannelSpec channel) => channel.id), <String>['orders', 'Promotions']);
    });

    test('on iOS init fetches no categories, since there are no channels', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await SignalPlus.init(config);
      await pumpEventQueue();

      expect(routes(), isEmpty);
      expect(push.channels, isEmpty);
    });

    test('a failed category fetch does not fail init', () async {
      harness.on(categoriesRoute, StubResponse.failure(500, <String>['InternalError']));

      expect((await SignalPlus.init(config)).isRight(), isTrue);
      await pumpEventQueue();

      expect(SignalPlus.isInitialized, isTrue);
      expect(push.channels, isEmpty);
    });

    test('registers the device by itself when registerOnStart is on', () async {
      await SignalPlus.init(
        const SignalPlusConfig(appId: ApiHarness.appId, locale: Some(ServiceLocale.ar), logger: Some(silent)),
      );
      await pumpEventQueue();

      expect(routes(), containsAll(<String>[register1, categoriesRoute]));
      expect(routes().where((final String route) => route == register1), hasLength(1));
      expect(secure.values[InstallationIdStore.key], 'install-1');
    });

    test('a failed start answers Left and can be tried again', () async {
      SignalPlusState.startPush =
          (final SignalPlusConfig _, final PushSettings _) async => throw StateError('no firebase');

      final ServiceFailure failure = leftOf(await SignalPlus.init(config));
      expect(failure.operation, Operations.init);
      expect(SignalPlus.isInitialized, isFalse);

      SignalPlusState.startPush = (final SignalPlusConfig _, final PushSettings _) async => push;
      expect((await SignalPlus.init(config)).isRight(), isTrue);
    });

    test('a fresh install drops the id and user the keychain kept', () async {
      local.values.clear();
      secure.values[ExternalIdStore.key] = 'old-user';
      secure.values[InstallationIdStore.key] = 'old-install';

      await SignalPlus.init(config);

      expect(rightOf(await SignalPlus.externalId()), const None());
      expect(rightOf(await SignalPlus.installationId()), isNot('old-install'));
      expect(local.values[FreshInstall.markerKey], '1');
    });

    test('every operation before init answers not initialized', () async {
      expect(leftOf(await SignalPlus.setLocale(ServiceLocale.ar)), SignalPlus.notInitialized);
      expect(leftOf(await SignalPlus.preferences()), SignalPlus.notInitialized);
      expect(leftOf(await SignalPlus.categories()), SignalPlus.notInitialized);
    });
  });

  group('registration', () {
    test('collects every field itself, under one installation id and with no secret', () async {
      start();

      final SdkInstallationEntity first = rightOf(await SignalPlus.setLocale(ServiceLocale.ar));
      harness.on(register1, StubResponse.data(view('install-1')));
      await SignalPlus.setLocale(ServiceLocale.en);

      expect(first.installationId, 'install-1');
      expect(body(0), <String, dynamic>{
        'Platform': 'Android',
        'Token': 't1',
        'PushPermission': 'Granted',
        'AppVersion': '1.1.1',
        'BuildNumber': '7',
        'Locale': 'ar',
        'TimeZone': 'Asia/Baghdad',
        'OsVersion': 'Android 15',
        'DeviceModel': 'Pixel 9',
      });
      expect(body(1)['Locale'], 'en');
      expect(routes(), <String>[register1, register1]);
      expect(noSecretSent(), isTrue);
    });

    test('a new token or permission re-registers once registered, the same state does not', () async {
      start();
      push.rotateToken('t1');
      await pumpEventQueue();
      expect(routes(), isEmpty);

      await SignalPlus.setLocale(ServiceLocale.ar);
      push.rotateToken('t1');
      await pumpEventQueue();
      push.rotateToken('t2');
      await pumpEventQueue();
      push.changePermission(PushPermission.denied);
      await pumpEventQueue();

      expect(routes(), hasLength(3));
      expect(body(1)['Token'], 't2');
      expect(body(2)['PushPermission'], 'Denied');
    });

    test('a token that arrives while registering is picked up and not sent twice', () async {
      start();

      final Future<Either<ServiceFailure, SdkInstallationEntity>> first = SignalPlus.setLocale(ServiceLocale.ar);
      push.rotateToken('t2');
      await first;
      await pumpEventQueue();

      expect(
        harness.requests.map((final RecordedRequest request) => (request.json! as Map<String, dynamic>)['Token']),
        <String>['t2'],
      );
    });

    test('a token failure answers Left and no request is sent', () async {
      start();
      push.tokenError = const Some(PushException('APNS_TOKEN_NOT_READY'));

      expect(leftOf(await SignalPlus.setLocale(ServiceLocale.ar)).operation, Operations.token);
      expect(routes(), isEmpty);
    });

    test('two calls run one after the other', () async {
      start();

      await Future.wait(<Future<Object>>[
        SignalPlus.setLocale(ServiceLocale.ar),
        SignalPlus.setLocale(ServiceLocale.en),
      ]);

      expect(<Object?>[body(0)['Locale'], body(1)['Locale']], <String>['ar', 'en']);
    });
  });

  group('sign-in', () {
    test('login signs this device in and keeps the external id', () async {
      start();
      harness.on(
        'POST /sdk/v1/installations/install-1/login',
        StubResponse.data(view('install-1', externalId: 'driver:42')),
      );

      final SdkInstallationEntity signedIn = rightOf(await SignalPlus.login('driver:42'));

      expect(routes(), <String>['POST /sdk/v1/installations/install-1/login']);
      expect(body(0), <String, dynamic>{'ExternalId': 'driver:42'});
      expect(signedIn.externalId, const Some('driver:42'));
      expect(rightOf(await SignalPlus.externalId()), const Some('driver:42'));
    });

    test('logout forgets the external id', () async {
      registered();
      secure.values[ExternalIdStore.key] = 'u';
      harness.on('POST /sdk/v1/installations/install-1/logout', StubResponse.data(view('install-1')));
      start();

      expect(rightOf(await SignalPlus.logout()).externalId, const None());
      expect(rightOf(await SignalPlus.externalId()), const None());
    });

    test('a device the service lost is registered again and the call tried once more', () async {
      registered();
      harness.on(register1, StubResponse.data(view('install-1')));
      harness.onSequence('POST /sdk/v1/installations/install-1/login', <StubResponse>[
        StubResponse.failure(404, <String>['InstallationNotFound']),
        StubResponse.data(view('install-1', externalId: 'u')),
      ]);
      start();

      expect((await SignalPlus.login('u')).isRight(), isTrue);
      expect(routes(), <String>[
        'POST /sdk/v1/installations/install-1/login',
        register1,
        'POST /sdk/v1/installations/install-1/login',
      ]);
    });

    test('a refused login answers Left and keeps no external id', () async {
      registered();
      harness.on('POST /sdk/v1/installations/install-1/login', StubResponse.failure(403, <String>['TenantSuspended']));
      start();

      expect(leftOf(await SignalPlus.login('u')).hasCode(ServiceErrorCodes.tenantSuspended), isTrue);
      expect(rightOf(await SignalPlus.externalId()), const None());
    });
  });

  group('the signed-in user', () {
    test('user functions act through this device id and send no secret', () async {
      registered();
      harness.on(
        'PUT /sdk/v1/installations/install-1/recipient/preferences',
        StubResponse.data(fixture('updated_preferences')),
      );
      harness.on('PUT /sdk/v1/installations/install-1/recipient/topics/city', StubResponse.data(fixture('topics')));
      start();

      await SignalPlus.updatePreferences(const <CategoryChoiceEntity>[
        CategoryChoiceEntity(key: 'Promotions', enabled: false),
      ]);
      await SignalPlus.subscribe('city');

      expect(routes(), <String>[
        'PUT /sdk/v1/installations/install-1/recipient/preferences',
        'PUT /sdk/v1/installations/install-1/recipient/topics/city',
      ]);
      expect(noSecretSent(), isTrue);
    });

    test('a device the service does not know yet is registered and the call tried once more', () async {
      harness.onSequence('GET /sdk/v1/installations/install-1/recipient/topics', <StubResponse>[
        StubResponse.failure(404, <String>['InstallationNotFound']),
        StubResponse.data(fixture('topics')),
      ]);
      start();

      expect(rightOf(await SignalPlus.recipientTopics()), <String>['city-baghdad', 'news']);
      expect(routes(), <String>[
        'GET /sdk/v1/installations/install-1/recipient/topics',
        register1,
        'GET /sdk/v1/installations/install-1/recipient/topics',
      ]);
    });

    test('NotSignedIn from the service forgets the saved external id', () async {
      registered();
      secure.values[ExternalIdStore.key] = 'u';
      harness.on(
        'GET /sdk/v1/installations/install-1/recipient/preferences',
        StubResponse.failure(403, <String>['NotSignedIn']),
      );
      start();

      expect(leftOf(await SignalPlus.preferences()).hasCode(ServiceErrorCodes.notSignedIn), isTrue);
      expect(rightOf(await SignalPlus.externalId()), const None());
    });
  });

  group('events', () {
    test('a tap reaches every listener and its NotifyId is reported as opened for this device', () async {
      registered();
      harness.on(
        'POST /sdk/v1/installations/install-1/notifications/ntf_01/events',
        StubResponse.data(<String, dynamic>{'Applied': true}),
      );
      final List<NotificationPayload> first = <NotificationPayload>[];
      final List<NotificationPayload> second = <NotificationPayload>[];
      listeners
        ..add(SignalPlus.onNotificationTap(first.add))
        ..add(SignalPlus.onNotificationTap(second.add));
      start();

      push.events.tap(const NotificationPayload(title: 'T', body: 'B', data: <String, dynamic>{'NotifyId': 'ntf_01'}));
      await pumpEventQueue();

      expect(first.single.notifyId, const Some('ntf_01'));
      expect(second, hasLength(1));
      expect(harness.last.route, 'POST /sdk/v1/installations/install-1/notifications/ntf_01/events');
      expect((harness.last.json! as Map<String, dynamic>)['Type'], 'Opened');
    });

    test('a tap without a NotifyId reports nothing', () async {
      start();

      expect(
        rightOf(
          await SignalPlus.reportOpened(const NotificationPayload(title: 'T', body: '', data: <String, dynamic>{})),
        ),
        isFalse,
      );
      expect(routes(), isEmpty);
    });

    test('the launch tap waits for a listener and is delivered once', () async {
      push.launch = const Some(NotificationPayload(title: 'Launch', body: '', data: <String, dynamic>{}));
      start();

      final List<NotificationPayload> first = <NotificationPayload>[];
      final List<NotificationPayload> second = <NotificationPayload>[];
      listeners.add(SignalPlus.onNotificationTap(first.add));
      listeners.add(SignalPlus.onNotificationTap(second.add));

      expect(first.single.title, 'Launch');
      expect(second, isEmpty);
    });

    test('a tap that arrives before the facade listens is not lost', () async {
      push.events.tap(const NotificationPayload(title: 'Early', body: '', data: <String, dynamic>{}));
      final List<NotificationPayload> taps = <NotificationPayload>[];
      listeners.add(SignalPlus.onNotificationTap(taps.add));

      start();

      expect(taps.single.title, 'Early');
    });

    test('a closure cannot be a background handler', () async {
      final ServiceFailure failure = leftOf(await SignalPlus.onBackgroundMessage((final RemoteMessage _) async {}));

      expect(failure.operation, BackgroundSettings.notTopLevel.operation);
    });

    test('foreground messages reach onMessage listeners', () async {
      final List<RemoteMessage> messages = <RemoteMessage>[];
      listeners.add(SignalPlus.onMessage(messages.add));
      start();

      push.events.message(const RemoteMessage(messageId: 'm1'));

      expect(messages.single.messageId, 'm1');
    });
  });

  group('display', () {
    test('init takes the app name from the app and names the default channel in its language', () async {
      Option<PushSettings> started = const None();
      SignalPlusState.startPush = (final SignalPlusConfig _, final PushSettings value) async {
        started = some(value);
        return push;
      };

      await SignalPlus.init(config);

      final PushSettings display = started.getOrElse(() => throw StateError('push did not start'));
      expect(display.appName, 'Shop');
      expect(display.locale, ServiceLocale.ar);
      expect(display.channelName, 'عامة');
      expect(display.channelDescription, 'إشعارات التطبيق العامة');
    });

    test(
      'setLocale renames the default channel, refreshes the category channels and saves the background display',
      () async {
        harness.on('GET /sdk/v1/categories', StubResponse.data(fixture('categories')));
        start();
        await SignalPlus.categories();
        push.channels.clear();

        await SignalPlus.setLocale(ServiceLocale.en);

        expect(push.channels.first.id, PushSettings.channelId);
        expect(push.channels.first.name, 'General');
        expect(push.channels.skip(1).map((final ChannelSpec channel) => channel.id), <String>['orders', 'Promotions']);
        expect(harness.last.headers['Accept-Language'], 'en');
        expect(secure.values[BackgroundSettings.configKey], contains('"Locale":"en"'));
      },
    );
  });

  group('language', () {
    test('setLocale registers the device in the new language and every later call asks for it', () async {
      harness.on('GET /sdk/v1/categories', StubResponse.data(fixture('categories')));
      start();

      await SignalPlus.setLocale(ServiceLocale.en);
      await SignalPlus.categories(createChannels: false);
      push.rotateToken('t2');
      await pumpEventQueue();

      expect(routes(), <String>[register1, 'GET /sdk/v1/categories', register1]);
      expect(body(0)['Locale'], 'en');
      expect(harness.requests[1].headers['Accept-Language'], 'en');
      expect(body(2)['Locale'], 'en');
    });

    test('before setLocale the configured language is used', () async {
      harness.on('GET /sdk/v1/categories', StubResponse.data(fixture('categories')));
      start();

      await SignalPlus.categories(createChannels: false);

      expect(harness.last.headers['Accept-Language'], 'ar');
    });
  });

  group('topics', () {
    test('the topics defined in the dashboard are listed with the App ID only, before anyone signs in', () async {
      harness.on('GET /sdk/v1/topics', StubResponse.data(fixture('topics')));
      start();

      expect(rightOf(await SignalPlus.topics()), <String>['city-baghdad', 'news']);
      expect(routes(), <String>['GET /sdk/v1/topics']);
    });
  });

  group('categories', () {
    test('create one channel per category on its Android channel id, before anyone signs in', () async {
      harness.on('GET /sdk/v1/categories', StubResponse.data(fixture('categories')));
      start();

      final List<CategoryEntity> categories = rightOf(await SignalPlus.categories());

      expect(categories, hasLength(2));
      expect(push.channels.map((final ChannelSpec channel) => channel.id), <String>['orders', 'Promotions']);
      expect(push.channels.first.name, 'الطلبات');
      expect(push.channels.last.description, '');
      expect(routes(), <String>['GET /sdk/v1/categories']);
    });

    test('can be listed without touching the channels', () async {
      harness.on('GET /sdk/v1/categories', StubResponse.data(fixture('categories')));
      start();

      expect(rightOf(await SignalPlus.categories(createChannels: false)), hasLength(2));
      expect(push.channels, isEmpty);
    });
  });

  test('push helpers answer through Either', () async {
    start();

    expect(rightOf(await SignalPlus.token()), 't1');
    expect(rightOf(await SignalPlus.permission()), PushPermission.granted);
    expect(rightOf(await SignalPlus.requestPermission()), PushPermission.granted);
    expect(rightOf(await SignalPlus.clearNotifications()), unit);
    expect(rightOf(await SignalPlus.deleteToken()), unit);
    expect(push.cleared, isTrue);
    expect(push.events.latestToken, const None());
  });

  test('the injected client is the one init uses', () {
    expect(SignalPlusState.createClient(config), isA<SignalPlusClient>());
  });
}
