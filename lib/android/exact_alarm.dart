import 'dart:io';
import 'package:flutter/services.dart';

/// Provides access to Android's exact alarm permission.
///
/// These methods are no-ops on non-Android platforms.
class ExactAlarm {
  ExactAlarm._();
  static const MethodChannel _channel = MethodChannel('exact_alarm');

  /// Returns whether the app is allowed to schedule exact alarms.
  static Future<bool> canSchedule() async {
    if (!Platform.isAndroid) return true;
    final result =
        await _channel.invokeMethod<bool>('canScheduleExactAlarms');
    return result ?? false;
  }

  /// Opens the platform settings screen to grant exact alarm permission.
  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('openExactAlarmSettings');
  }
}

