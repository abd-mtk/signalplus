final class PushConfig {
  const PushConfig({
    this.requestPermissionOnStartup = true,
    this.showForegroundNotification = true,
    this.showNotificationImages = true,
    this.groupNotifications = false,
    this.clearNotificationsOnLaunch = false,
    this.openLinks = true,
  });

  final bool requestPermissionOnStartup;

  final bool showForegroundNotification;

  final bool showNotificationImages;

  final bool groupNotifications;

  final bool clearNotificationsOnLaunch;

  final bool openLinks;
}
