import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/domain/entities/enums.dart';
import '../core/kits/domain_kit.dart';
import '../core/utils/logger.dart';
import '../core/utils/memo.dart';

final class DeviceSnapshot extends Equatable {
  const DeviceSnapshot({
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    required this.timeZone,
    this.appName = '',
    this.osVersion = const None(),
    this.deviceModel = const None(),
  });

  final DevicePlatform platform;

  final String appVersion;

  final String buildNumber;

  final String timeZone;

  final String appName;

  final Option<String> osVersion;

  final Option<String> deviceModel;

  @override
  List<Object> get props => <Object>[platform, appVersion, buildNumber, timeZone, appName, osVersion, deviceModel];
}

abstract class DeviceSnapshotReader {
  Future<DeviceSnapshot> read();
}

final class PlatformDeviceSnapshotReader implements DeviceSnapshotReader {
  PlatformDeviceSnapshotReader({this.logger = const KitLogger(sink: KitLogger.silentSink)});

  static const String fallbackTimeZone = 'UTC';

  final KitLogger logger;

  final Memo<DeviceSnapshot> cached = Memo<DeviceSnapshot>();

  @override
  Future<DeviceSnapshot> read() => cached(load);

  Future<DeviceSnapshot> load() async {
    final PackageInfo package = await PackageInfo.fromPlatform();
    final ({String os, String model}) device = await readDevice();
    return DeviceSnapshot(
      platform: Platform.isIOS ? DevicePlatform.ios : DevicePlatform.android,
      appVersion: package.version,
      buildNumber: package.buildNumber,
      timeZone: await readTimeZone(),
      appName: package.appName,
      osVersion: device.os.nonEmpty,
      deviceModel: device.model.nonEmpty,
    );
  }

  Future<({String os, String model})> readDevice() async {
    final DeviceInfoPlugin plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final IosDeviceInfo info = await plugin.iosInfo;
      return (os: 'iOS ${info.systemVersion}', model: info.utsname.machine);
    }
    final AndroidDeviceInfo info = await plugin.androidInfo;
    return (os: 'Android ${info.version.release}', model: info.model);
  }

  Future<String> readTimeZone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object catch (error) {
      logger.error('Time zone unavailable, using $fallbackTimeZone', error);
      return fallbackTimeZone;
    }
  }
}
