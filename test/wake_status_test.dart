//widget_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:team_alarm1_2/core/wake_status.dart';

void main() {
  final now = DateTime(2024, 1, 1, 8, 0);

  test('returns noAlarm when alarm is null', () {
    expect(computeStatus(now: now, alarm: null, post: null), WakeCellStatus.noAlarm);
  });

  test('returns waiting before alarm', () {
    final alarm = TodayAlarm(uid: 'u', alarmAt: now.add(const Duration(minutes: 5)), graceMins: 10);
    expect(computeStatus(now: now, alarm: alarm, post: null), WakeCellStatus.waiting);
  });

  test('returns due within grace period', () {
    final alarm = TodayAlarm(uid: 'u', alarmAt: now.subtract(const Duration(minutes: 5)), graceMins: 10);
    expect(computeStatus(now: now, alarm: alarm, post: null), WakeCellStatus.due);
  });

  test('returns lateSuspicious after grace period', () {
    final alarm = TodayAlarm(uid: 'u', alarmAt: now.subtract(const Duration(minutes: 20)), graceMins: 5);
    expect(computeStatus(now: now, alarm: alarm, post: null), WakeCellStatus.lateSuspicious);
  });

  test('returns posted when post exists', () {
    final alarm = TodayAlarm(uid: 'u', alarmAt: now, graceMins: 10);
    final post = GridPost(uid: 'u', type: 'button');
    expect(computeStatus(now: now, alarm: alarm, post: post), WakeCellStatus.posted);
  });

  test('returns snoozing when within snooze window', () {
    final alarm = TodayAlarm(
      uid: 'u',
      alarmAt: now.subtract(const Duration(minutes: 5)),
      graceMins: 10,
      lastSnoozedAt: now.subtract(const Duration(minutes: 1)),
      snoozeMins: 5,
    );
    expect(computeStatus(now: now, alarm: alarm, post: null), WakeCellStatus.snoozing);
  });
}