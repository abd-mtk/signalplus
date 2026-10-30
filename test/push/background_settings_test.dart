import 'package:flutter_test/flutter_test.dart';
import 'package:signalplus/signalplus.dart';
import 'package:signalplus/src/push/models/push_settings.dart';
import 'package:signalplus/src/signal_plus/background_entry.dart';

import '../support/device_fakes.dart';

void main() {
  test('the display config survives for the background isolate', () async {
    final MemoryStore store = MemoryStore();

    await BackgroundSettings.saveConfig(
      store,
      const PushSettings(
        appName: 'App',
        locale: ServiceLocale.en,
        options: PushConfig(showNotificationImages: false, groupNotifications: true),
      ),
    );
    final PushSettings config = (await BackgroundSettings.readConfig(
      store,
    )).getOrElse(() => throw StateError('no config'));

    expect(config.appName, 'App');
    expect(config.locale, ServiceLocale.en);
    expect(config.channelName, 'General notifications');
    expect(config.options.showNotificationImages, isFalse);
    expect(config.options.groupNotifications, isTrue);
  });

  test('a config saved by 0.1.0 is still read, in Arabic', () async {
    final MemoryStore store =
        MemoryStore()
          ..values[BackgroundSettings.configKey] =
              '{"AppName":"App","ChannelName":"C","ChannelDescription":"D","Icon":"@mipmap/ic_launcher",'
              '"Logs":true,"Group":false,"Images":true}';

    final PushSettings config = (await BackgroundSettings.readConfig(
      store,
    )).getOrElse(() => throw StateError('no config'));

    expect(config.appName, 'App');
    expect(config.locale, ServiceLocale.ar);
  });

  test('nothing is read when nothing was saved', () async {
    expect(await BackgroundSettings.readConfig(MemoryStore()), const None());
    expect(await BackgroundSettings.readHandler(MemoryStore()), const None());
  });
}
