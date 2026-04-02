import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications.
///
/// Provides OS-level fall-alert notifications so the caretaker is notified
/// even when the app is not in the foreground.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'ican_fall_alerts',
    'Fall Alerts',
    description: 'Urgent notifications when a fall is detected by iCan Cane.',
    importance: Importance.max,
    playSound: true,
  );

  static const _androidDetails = AndroidNotificationDetails(
    'ican_fall_alerts',
    'Fall Alerts',
    channelDescription:
        'Urgent notifications when a fall is detected by iCan Cane.',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'Fall detected',
    icon: '@mipmap/ic_launcher',
  );

  static const _iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    sound: 'default',
    interruptionLevel: InterruptionLevel.timeSensitive,
  );

  static const _notificationDetails = NotificationDetails(
    android: _androidDetails,
    iOS: _iosDetails,
  );

  /// Call once in main() before runApp().
  static Future<void> init() async {
    const initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: initSettingsAndroid,
      iOS: initSettingsIOS,
    );

    await _plugin.initialize(initSettings);

    // Create the Android notification channel
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);

    debugPrint('[Notifications] Initialized.');
  }

  /// Show an urgent fall-detected notification.
  static Future<void> showFallAlert() async {
    debugPrint('[Notifications] Showing fall alert notification.');
    await _plugin.show(
      0, // notification ID (0 = replace previous fall alert)
      'Fall Detected',
      'iCan Cane has detected a fall. Check on the user immediately.',
      _notificationDetails,
    );
  }

  /// Cancel the active fall alert notification (call after caretaker acknowledges).
  static Future<void> cancelFallAlert() async {
    await _plugin.cancel(0);
    debugPrint('[Notifications] Fall alert notification dismissed.');
  }
}
