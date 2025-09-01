//notifications/notification_service.dart（ローカル通知・スヌーズ）

import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _fln = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false,
    );
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android, iOS: ios);
    await _fln.initialize(init);
  }

  Future<void> requestPermissions() async {
    if (Platform.isIOS) {
      await _fln.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      _fln
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> scheduleAlarm({
    required int id, required DateTime alarmAtLocal, String? title, String? body, String? payload,
  }) async {
    final t = tz.TZDateTime.from(alarmAtLocal, tz.local);
    const android = AndroidNotificationDetails(
      'alarm_channel_id', 'Morning Alarms',
      channelDescription: 'Alarm notifications for wake-up',
      importance: Importance.max, priority: Priority.high, playSound: true,
      category: AndroidNotificationCategory.alarm, fullScreenIntent: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    await _fln.zonedSchedule(
      id, title ?? 'おはようの時間です', body ?? 'グリッドに投稿しましょう', t,
      const NotificationDetails(android: android, iOS: ios),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidAllowWhileIdle: true, payload: payload,
    );
  }

  Future<void> cancel(int id) => _fln.cancel(id);

  Future<void> snooze({required int id, required int minutes, String? title, String? body, String? payload}) async {
    final next = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    const android = AndroidNotificationDetails(
      'alarm_channel_id','Morning Alarms',
      channelDescription: 'Alarm notifications for wake-up',
      importance: Importance.max, priority: Priority.high, playSound: true,
      category: AndroidNotificationCategory.alarm, fullScreenIntent: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    await _fln.zonedSchedule(
      id, title ?? 'スヌーズ', body ?? 'そろそろ起きる時間です', next,
      const NotificationDetails(android: android, iOS: ios),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidAllowWhileIdle: true, payload: payload,
    );
  }
}
