import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _flnp = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _flnp.initialize(initSettings);

    // --- iOS: 明示的に通知許可をリクエストし、状態をログ出力 ---
    if (Platform.isIOS) {
      final iosImpl = _flnp.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
      /*try {
        final settings = await iosImpl?.getNotificationSettings();
        // ignore: avoid_print
        print('[iOS Notification Settings] authorizationStatus=${settings?.authorizationStatus} alert=${settings?.alertSetting} sound=${settings?.soundSetting}');
      } catch (_) {
        // iOS plugin 版によっては未サポートのことがあるので握りつぶし
      }*/
    }

    // Android 13+ の通知許可
    if (Platform.isAndroid) {
      final impl = _flnp.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await impl?.requestNotificationsPermission();
    }

    // Android 12+ (API 31+) の正確なアラーム権限 (SCHEDULE_EXACT_ALARM)
    if (Platform.isAndroid) {
      final androidImpl = _flnp.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // 一部端末では無視される場合もあるが、サポートされていれば設定画面を開く
      await androidImpl?.requestExactAlarmsPermission();
    }
  }

  /// 1回だけ鳴らす
  Future<void> scheduleAlarm({
    required int id,
    required DateTime at,
    String title = '起床時間です',
    String body = 'おはようを投稿しましょう',
  }) async {
    // ★ チャンネルIDは新しいものに（過去の設定を引きずらないため）
    const channelId = 'alarm_channel_v2';
    final androidDetails = AndroidNotificationDetails(
      channelId,
      'Alarms',
      channelDescription: 'Alarm notifications',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_elegant'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
    );

    const iosDetails = DarwinNotificationDetails(
      sound: 'alarm_elegant.caf', // iOSは拡張子付き
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentSound: true,
    );

    final nowTz = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime.from(at, tz.local);
    if (!scheduled.isAfter(nowTz.add(const Duration(seconds: 1)))) {
      // 過去や即時は捨てられるのを防ぐため、直近未来に補正
      scheduled = nowTz.add(const Duration(seconds: 5));
    }

    await _flnp.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.wallClockTime,
    );

    // iOS only: chain a few follow-up notifications (~10s apart) to extend audible duration on Home/Lock.
    if (Platform.isIOS) {
      final iosDetailsFollow = const DarwinNotificationDetails(
        sound: 'alarm_elegant.caf',
        interruptionLevel: InterruptionLevel.timeSensitive,
        presentAlert: true,
        presentSound: true,
      );
      final n1 = scheduled.add(const Duration(seconds: 10));
      final n2 = scheduled.add(const Duration(seconds: 20));
      // Use offset IDs to avoid clobbering the base one; caller may cancel(id) and optionally cancel(id+1, id+2)
      await _flnp.zonedSchedule(
        id + 1,
        title,
        body,
        n1,
        NotificationDetails(android: androidDetails, iOS: iosDetailsFollow),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      );
      await _flnp.zonedSchedule(
        id + 2,
        title,
        body,
        n2,
        NotificationDetails(android: androidDetails, iOS: iosDetailsFollow),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      );
    }
  }

  Future<void> cancel(int id) => _flnp.cancel(id);

  Future<void> showNowTest() async {
    const channelId = 'alarm_channel_test_v1'; // 新IDで

    final android = AndroidNotificationDetails(
      channelId,
      'Alarms',
      channelDescription: 'Alarm test channel',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_elegant'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      // sound はまずデフォルトで切り分け、問題なければ 'alarm_onsei1.caf' に差し替える
      // sound: 'alarm_onsei1.caf',
    );

    await _flnp.show(
      777,
      '即時テスト',
      '今すぐ鳴るはずです',
      NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> requestPermissions() async {
    if (Platform.isIOS) {
      await _flnp
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      await _flnp
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  /// スヌーズ（単発再スケジュール）
  Future<void> snooze({required int id, required int minutes}) async {
    final next = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));

    const channelId = 'alarm_channel_v2'; // scheduleAlarm と同じに統一
    final a = AndroidNotificationDetails(
      channelId,
      'Alarms',
      channelDescription: 'Alarm notifications',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_onsei1'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    const i = DarwinNotificationDetails(
      sound: 'alarm_elegant.caf',
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentSound: true,
    );

    await _flnp.zonedSchedule(
      id,
      'スヌーズ',
      'そろそろ起きる時間です',
      next,
      NotificationDetails(android: a, iOS: i),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.wallClockTime,
    );

    if (Platform.isIOS) {
      const iosFollow = DarwinNotificationDetails(
        sound: 'alarm_elegant.caf',
        interruptionLevel: InterruptionLevel.timeSensitive,
        presentAlert: true,
        presentSound: true,
      );
      final n1 = next.add(const Duration(seconds: 10));
      final n2 = next.add(const Duration(seconds: 20));
      await _flnp.zonedSchedule(
        id + 1,
        'スヌーズ',
        'そろそろ起きる時間です',
        n1,
        NotificationDetails(android: a, iOS: iosFollow),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      );
      await _flnp.zonedSchedule(
        id + 2,
        'スヌーズ',
        'そろそろ起きる時間です',
        n2,
        NotificationDetails(android: a, iOS: iosFollow),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
      );
    }
  }

  /// 今から [seconds] 秒後にテスト用の正確アラームを設定（動作確認用）
  Future<void> scheduleAfterSeconds({int id = 991, int seconds = 15}) async {
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    await scheduleAlarm(id: id, at: when, title: 'テストアラーム', body: '数秒後テスト');
  }

  /// Android の通知・正確アラーム権限を（可能なら）明示的にリクエスト
  Future<void> ensureAndroidAlarmPermissions() async {
    if (!Platform.isAndroid) return;
    final androidImpl = _flnp.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  /// デバッグ用: 権限・保留中通知・表示テストをまとめて実行
  Future<void> debugDiagnostics() async {
    // iOS/Android 共通: ペンディングの通知一覧を出力
    final pending = await _flnp.pendingNotificationRequests();
    // ignore: avoid_print
    print('[LocalNotifications] pending=${pending.length} ids=${pending.map((e) => e.id).toList()}');

    // 直ちに1件表示（バナー＋サウンド）
    await showNowTest();

    // 数秒後アラームも設定
    await scheduleAfterSeconds(id: 992, seconds: 5);
  }

  Future<void> cancelFamily(int baseId) async {
    await _flnp.cancel(baseId);
    await _flnp.cancel(baseId + 1);
    await _flnp.cancel(baseId + 2);
  }
}