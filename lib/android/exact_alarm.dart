//android/exact_alarm.dart

import 'dart:io';
import 'package:flutter/services.dart';

class ExactAlarm {
  static const _ch = MethodChannel('exact_alarm');
  static Future<bool> canSchedule() async {
    if (!Platform.isAndroid) return true;
    try { return await _ch.invokeMethod<bool>('canScheduleExactAlarms') ?? true; } catch (_) { return true; }
  }
  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try { await _ch.invokeMethod('openExactAlarmSettings'); } catch (_) {}
  }
}
