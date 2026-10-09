import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Opt-in daily reminder that a new Daily Challenge is live. Scheduled on
/// the device (no push server).
class ReminderService {
  ReminderService({bool? enabled})
    : enabled = enabled ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  final bool enabled;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const _id = 1;

  Future<void> init() async {
    if (!enabled || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Turns the reminder on (asking for permission) or off. Returns whether
  /// it is on afterwards.
  Future<bool> setDailyReminder(bool on) async {
    if (!enabled) return false;
    await init();
    if (!_ready) return false;
    try {
      if (!on) {
        await _plugin.cancel(id: _id);
        return false;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted =
          await android?.requestNotificationsPermission() ??
          await ios?.requestPermissions(alert: true, sound: true) ??
          false;
      if (!granted) return false;
      await _plugin.periodicallyShow(
        id: _id,
        title: 'New Daily Challenge',
        body: 'A fresh Hue Lock challenge is live. Keep your streak going!',
        repeatInterval: RepeatInterval.daily,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily',
            'Daily Challenge',
            channelDescription: 'A reminder when a new Daily Challenge is live',
            importance: Importance.defaultImportance,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint('Daily reminder failed: $e');
      return false;
    }
  }
}
