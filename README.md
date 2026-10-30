# signalplus

Push notifications for Flutter apps on SignalPlus. Receive notifications, sign users in and out, and let them manage their notification settings and topics. All you need is your environment's **App ID**: no API key in the app, and no code on your backend.

```dart
await SignalPlus.init(const SignalPlusConfig(appId: 'sdk_01J9…'));
await SignalPlus.login(user.id);
```

## Contents

- [Installation](#installation)
- [Platform setup](#platform-setup)
- [Quick start](#quick-start)
- [Signing in and out](#signing-in-and-out)
- [Language](#language)
- [Receiving notifications](#receiving-notifications)
- [Notification settings](#notification-settings)
- [Topics](#topics)
- [Permission](#permission)
- [Results and errors](#results-and-errors)
- [Configuration](#configuration)
- [API reference](#api-reference)
- [Limitations](#limitations)

---

## Installation

```yaml
dependencies:
  signalplus:
    git:
      url: https://github.com/abd-mtk/signalplus.git
      ref: main
```

```dart
import 'package:signalplus/signalplus.dart';
```

Copy your App ID (`sdk_…`) from the dashboard: **Environment → App SDK**. It is not a secret, and it is not the environment id (`env_…`).

---

## Platform setup

1. Connect the app to Firebase: `flutterfire configure`. It adds `google-services.json` and `GoogleService-Info.plist`.
2. Upload an **APNs authentication key** (`.p8`) in Firebase Console → Project settings → Cloud Messaging.
3. From your app's root:

   ```bash
   dart run signalplus:setup
   ```

   It changes only what is missing, so it is safe to run again:

   - **Android:** turns on core library desugaring in `android/app/build.gradle(.kts)`, and raises `compileSdk` to 35 and `minSdk` to 24 when they are set lower.
   - **iOS:** turns on Push Notifications and Background Modes → Remote notifications, and adds the extension that shows notification images. It needs the `xcodeproj` gem, which CocoaPods already installs.

Nothing goes in `AndroidManifest.xml`: the package brings the notification permission, the default channel and the notification icon in its own manifest.

**The notification icon.** On Android, put your own as `android/app/src/main/res/drawable/ic_notification.png`: a white shape on a transparent background. Without it, the package's bell is used. On iOS, notifications always show the app icon.

If your app already sets `com.google.firebase.messaging.default_notification_icon` or `default_notification_channel_id` to another value, add `tools:replace="android:resource"` (or `android:value`) to that `<meta-data>`, as the build error suggests.

Test on a real device; the simulator does not receive push reliably.

---

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:signalplus/signalplus.dart';

Future<void> main() async {
  await SignalPlus.init(const SignalPlusConfig(appId: 'sdk_01J9…'));

  SignalPlus.onNotificationTap((final NotificationPayload payload) => openScreen(payload.data));

  runApp(const MyApp());
}
```

`init` sets up Firebase and the notification channels, asks for permission, and registers the device. On Android it also creates one channel per category from the dashboard, on every start, so new categories and renamed ones reach the app without an update. Notifications show by themselves in every state: open, in the background, or closed. From then on the device keeps itself up to date: every new Firebase Installation ID or permission change registers it again by itself.

The device registers with FCM by its Firebase Installation ID (`register` / `onRegistered`), not by the deprecated FCM token. On Android the package turns this on in its own manifest, so your app must not call `FirebaseMessaging.getToken()` or `deleteToken()` itself: with the flag on, they throw.

---

## Signing in and out

```dart
// After the user signs in to your app
await SignalPlus.login(user.id);

// When the user signs out
await SignalPlus.logout();
```

- `login` links this device to the user, using their id in your system. The user is created if new.
- `logout` unlinks the device, so the next person on this phone does not get the previous user's notifications. It is all SignalPlus needs on sign-out.

---

## Language

By default the package follows the device language. If your app has its own language setting, pass it to `init` as `locale: Some(ServiceLocale.en)`, and when the user changes it:

```dart
await SignalPlus.setLocale(ServiceLocale.en);
```

One call updates the device, the signed-in user and the Android channel names. The time zone follows the device by itself.

---

## Receiving notifications

```dart
// The app is open
SignalPlus.onMessage((final RemoteMessage message) {});

// The user taps a notification (also the tap that launched the app)
SignalPlus.onNotificationTap((final NotificationPayload payload) {
  final Object? route = payload.data['route'];
  if (route is String) navigatorKey.currentState?.pushNamed(route);
});
```

- Taps are reported as opened automatically.
- `payload.data` holds every key your backend sent with the notification.
- Notifications that arrive while the app is in the background or closed are shown by the package itself; you write nothing for them.

**Optional: your own code while the app is closed.** To run code of yours when a notification arrives in the background (for example, to update a local database), pass a function that is declared at the top level of a file, outside any class:

```dart
@pragma('vm:entry-point')
Future<void> onBackground(final RemoteMessage message) async {
  // Runs in a separate isolate: nothing from main() is available here.
}

await SignalPlus.onBackgroundMessage(onBackground);
```

---

## Notification settings

```dart
// Read: every category with its state, and the quiet hours
final PreferencesEntity settings =
    (await SignalPlus.preferences()).getOrElse((_) => throw StateError('offline'));

// Turn a category off
await SignalPlus.updatePreferences(<CategoryChoiceEntity>[
  const CategoryChoiceEntity(key: 'Promotions', enabled: false),
]);

// Quiet hours, in the user's time zone
await SignalPlus.setQuietHours(
  const QuietHoursEntity(start: '23:00', end: '07:00', days: <WeekDay>[WeekDay.thu, WeekDay.fri]),
);
await SignalPlus.clearQuietHours();
```

A locked category cannot be turned off; it comes back in `rejected`.

---

## Topics

Topics are created in the dashboard (**Environment → Topics**). The app lists them and lets the user follow the ones they want:

```dart
final List<String> available = (await SignalPlus.topics()).getOrElse((_) => <String>[]);
final List<String> following = (await SignalPlus.recipientTopics()).getOrElse((_) => <String>[]);

await SignalPlus.subscribe('news');
await SignalPlus.unsubscribe('news');
```

---

## Permission

By default, `init` asks for permission. To ask at a better moment instead, set `requestPermissionOnStartup: false` and call:

```dart
final PushPermission permission = (await SignalPlus.requestPermission()).getOrElse((_) => PushPermission.denied);
```

`SignalPlus.permission()` reads the current state without asking.

---

## Results and errors

Every call returns `Either<ServiceFailure, T>` and never throws:

```dart
(await SignalPlus.subscribe('news')).match(
  (final ServiceFailure failure) {
    if (failure.hasCode(ServiceErrorCodes.notSignedIn)) return openSignIn();
    if (failure.type.isNetwork) return showOffline();
    showError(failure.message); // already in the user's language
  },
  (final List<String> topics) => showTopics(topics),
);
```

| Code                                 | When                                           |
| ------------------------------------ | ---------------------------------------------- |
| `ServiceErrorCodes.notSignedIn`      | A user call before `login`.                    |
| `ServiceErrorCodes.topicNotFound`    | The topic was not created in the dashboard.    |
| `ServiceErrorCodes.appIdInvalid`     | The App ID is wrong.                           |
| `ServiceErrorCodes.validationFailed` | A value is invalid; see `failure.fieldErrors`. |
| `ServiceErrorCodes.rateLimited`      | Too many requests; try again later.            |

`failure.type.isNetwork` is `true` when there is no connection or the request timed out.

---

## Configuration

### SignalPlusConfig

| Option            | Default                                                       | Description                                                                                     |
| ----------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `appId`           | **required**                                                  | The environment's App ID (`sdk_…`).                                                             |
| `locale` | the device language | `Some(ServiceLocale.ar)` or `Some(ServiceLocale.en)`, for apps with their own language setting. |
| `push`            | `PushConfig()`                                                | How notifications are shown (below).                                                            |
| `registerOnStart` | `true`                                                        | Register the device right after `init`.                                                         |
| `logger`          | debug builds only                                             | `Some((tag, message) => …)` to send the package's logs to your own logger.                      |
| `firebaseOptions` | read from `google-services.json` / `GoogleService-Info.plist` | Only for apps without those files, such as flavors that each point at another Firebase project. |

### PushConfig

| Option                       | Default | Description                                       |
| ---------------------------- | ------- | ------------------------------------------------- |
| `requestPermissionOnStartup` | `true`  | Ask for permission in `init`.                     |
| `showForegroundNotification` | `true`  | Show notifications while the app is open.         |
| `showNotificationImages`     | `true`  | Show the images notifications carry.              |
| `groupNotifications`         | `false` | Group notifications under one summary on Android. |
| `clearNotificationsOnLaunch` | `false` | Clear shown notifications when the app starts.    |

Everything else is set by the package: the app's name, the notification icon (your `ic_notification`, otherwise the package's bell), and the default channel name and group summary, in the app's language.

---

## API reference

| Call                                              | Returns                    | Purpose                                                             |
| ------------------------------------------------- | -------------------------- | ------------------------------------------------------------------- |
| `init(config)`                                    | `Unit`                     | Set everything up and register the device.                          |
| `login(externalId)`                               | `SdkInstallationEntity`    | Link this device to the signed-in user.                             |
| `logout()`                                        | `SdkInstallationEntity`    | Unlink the user from this device.                                   |
| `setLocale(locale)`                               | `SdkInstallationEntity`    | Change the app's language.                                          |
| `onMessage(handler)`                              | `StreamSubscription`       | Notifications while the app is open.                                |
| `onNotificationTap(handler)`                      | `StreamSubscription`       | Taps, including the launch tap.                                     |
| `onBackgroundMessage(handler)`                    | `Unit`                     | Optional: your own code for notifications that arrive while closed. |
| `preferences()`                                   | `PreferencesEntity`        | Categories and quiet hours.                                         |
| `updatePreferences(choices)`                      | `UpdatedPreferencesEntity` | Turn categories on or off.                                          |
| `setQuietHours(quietHours)` / `clearQuietHours()` | `PreferencesEntity`        | Quiet hours.                                                        |
| `topics()`                                        | `List<String>`             | Topics available to follow.                                         |
| `recipientTopics()`                               | `List<String>`             | Topics the user follows.                                            |
| `subscribe(topic)` / `unsubscribe(topic)`         | `List<String>`             | Follow or unfollow a topic.                                         |
| `categories()`                                    | `List<CategoryEntity>`     | The categories, for your own settings screen.                       |
| `requestPermission()` / `permission()`            | `PushPermission`           | Ask for, or read, the permission.                                   |
| `clearNotifications()`                            | `Unit`                     | Remove shown notifications.                                         |
| `externalId()`                                    | `Option<String>`           | The user signed in on this device.                                  |
| `installationId()`                                | `String`                   | This device's id.                                                   |

---

## Limitations

- **iOS data-only messages** are throttled and not delivered after a force-quit.
