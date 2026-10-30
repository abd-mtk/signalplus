## 0.2.2

* The default channel is named `General Notifications` / `الإشعارات العامة` again.

## 0.2.1

* The default channel is named `General` / `عامة`, with the description `General App Notifications` / `إشعارات التطبيق العامة`.
* The English group summary reads `1 New Notification` / `3 New Notifications`.

## 0.2.0

Less to configure: the package works out what it can by itself.

* **Breaking:** `PushConfig` keeps only the five display switches. `notificationIcon`, `enableLogs`, `groupSummary`, `PushConfig.resolved`, `display`, `localized`, `toJson` and `fromJson` are gone.
* **Breaking:** `logger` moved from `PushConfig` to `SignalPlusConfig`. Without one, the package logs in debug builds only (release builds used to print too).
* The Android notification icon is found by itself: `@drawable/ic_notification` when the app ships it, otherwise `@mipmap/ic_launcher`. An app whose launcher icon has another name no longer fails `init`.
* **Breaking:** the device registers with FCM by its Firebase Installation ID (`register`, `onRegistered`, `unregister`) instead of the deprecated `getToken`, `onTokenRefresh` and `deleteToken`. On Android the package sets `firebase_messaging_installation_id_enabled` in its own manifest, so nothing is added to the app; an app that still calls `getToken()` or `deleteToken()` itself gets an `IllegalStateException` on Android. The service keeps sending through the FCM `token` field, which accepts FIDs while Firebase migrates.
* `init` creates one Android channel per category by itself, on every start; calling `categories()` for that is no longer needed. iOS has no channels, so nothing is fetched there.
* Fix: a category notification that arrived while the app was closed went to the default channel. The channels Android already keeps are now read at start, in the background isolate too.
* **Breaking:** `SignalPlusConfig.locale` is optional and follows the device language; pass `Some(ServiceLocale.en)` for an app with its own language setting.
* **Breaking:** `dart run signalplus:setup` replaces `setup_ios` and covers both platforms: desugaring and SDK levels in Gradle on Android; Push Notifications, Background Modes and the image extension on iOS. Safe to run again.
* Nothing goes in `AndroidManifest.xml` any more: the package's manifest brings the default channel and the notification icon, with a default bell that an app's own `ic_notification` replaces.
* `init` calls `WidgetsFlutterBinding.ensureInitialized()` itself.
* The group summary is written in the app's language, and notifications that arrive while the app is closed now use the same words as the rest.

## 0.1.0

The first release of `signalplus`: one static facade, `SignalPlus`, that receives push notifications and lets the signed-in user manage their own notification settings, through the SignalPlus SDK API (`/sdk/v1`) with the environment's public App ID. No API key in the app, no proxy in your backend.

* `SignalPlus.init(SignalPlusConfig(appId:, locale:))` sets up Firebase, the Android channels and the client, and registers the device by itself.
* The device registers again on every FCM token or permission change, under one installation id per install; a device the service no longer knows is registered again and the call retried once.
* `login(externalId)` and `logout()` link and unlink the signed-in user.
* `setLocale(ServiceLocale)` changes the language of the device and the signed-in user in one call; the time zone follows the device.
* Notification settings: `preferences`, `updatePreferences`, `setQuietHours`, `clearQuietHours`.
* Topics created in the dashboard: `topics`, `recipientTopics`, `subscribe`, `unsubscribe`.
* `categories()` creates one Android channel per category, before anyone signs in.
* Taps report `Opened` by themselves; `reportOpened` covers opens you handle yourself.
* Events: `onMessage` and `onNotificationTap` (including the launch tap). Notifications that arrive in the background or while the app is closed are shown by the package itself; `onBackgroundMessage` optionally runs your own code for them.
* The app name and the default channel (`signalplus_default`) are set by the package, named in the app's language.
* Every call returns `Either<ServiceFailure, T>` and never throws.
