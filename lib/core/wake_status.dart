//状態判断
import 'package:cloud_firestore/cloud_firestore.dart';

enum WakeCellStatus { noAlarm, waiting, due, lateSuspicious, posted,snoozing }

class TodayAlarm {
  final String uid;
  final DateTime? alarmAt;
  final int graceMins;
  final DateTime? lastSnoozedAt;
  final int snoozeMins;
  TodayAlarm({
    required this.uid,
    required this.alarmAt,
    required this.graceMins,
    this.lastSnoozedAt,
    this.snoozeMins = 0,
  });

  factory TodayAlarm.fromMap(String uid, Map<String, dynamic> m) => TodayAlarm(
    uid: uid,
    alarmAt: (m['alarmAt'] as Timestamp?)?.toDate(),
    graceMins: (m['graceMins'] as int?) ?? 10,
    lastSnoozedAt: (m['lastSnoozedAt'] as Timestamp?)?.toDate(),
    snoozeMins: (m['snoozeMins'] as int?) ?? 0,
  );
}

class GridPost {
  final String uid;
  final String type; // "button" | "photo"
  final String? text;
  final String? photoUrl;
  GridPost({required this.uid, required this.type, this.text, this.photoUrl});
  factory GridPost.fromMap(String uid, Map<String, dynamic> m) => GridPost(
    uid: uid,
    type: (m['type'] as String?) ?? 'button',
    text: m['text'] as String?,
    photoUrl: m['photoUrl'] as String?,
  );
}

WakeCellStatus computeStatus({
  required DateTime now,
  required TodayAlarm? alarm,
  required GridPost? post,
}) {
  if (post != null) return WakeCellStatus.posted;
  if (alarm == null || alarm.alarmAt == null) return WakeCellStatus.noAlarm;

  if (alarm.lastSnoozedAt != null) {
    final snoozeEnd = alarm.lastSnoozedAt!.add(Duration(minutes: alarm.snoozeMins));
    if (now.isBefore(snoozeEnd)) return WakeCellStatus.snoozing;
  }


  final due = alarm.alarmAt!;
  final graceEnd = due.add(Duration(minutes: alarm.graceMins));
  if (now.isBefore(due)) return WakeCellStatus.waiting;
  if (now.isBefore(graceEnd)) return WakeCellStatus.due;
  return WakeCellStatus.lateSuspicious;
}
