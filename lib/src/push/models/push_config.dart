final class PushConfig {
  const PushConfig({
    this.requestPermissionOnStartup = true,
    this.showForegroundNotification = true,
    this.showNotificationImages = true,
    this.groupNotifications = false,
    this.clearNotificationsOnLaunch = false,
  });

  final bool requestPermissionOnStartup;

  final bool showForegroundNotification;

  final bool showNotificationImages;

  final bool groupNotifications;

  final bool clearNotificationsOnLaunch;
}
