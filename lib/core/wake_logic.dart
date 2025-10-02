import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/grid_post.dart';
import 'package:team_alarm1_2/core/wake_cell_status.dart';
export 'package:team_alarm1_2/core/wake_cell_status.dart';


class TodayAlarm {
  final String uid;
  final DateTime? alarmAt;
  final int graceMins;
  final int snoozeCount;
  final bool snoozing;
  final DateTime? wakeAt; // 実際に起きた時刻（固定表示用）

  TodayAlarm({
    required this.uid,
    required this.alarmAt,
    required this.graceMins,
    required this.snoozeCount,
    required this.snoozing,
    required this.wakeAt,
  });

  factory TodayAlarm.fromMap(String uid, Map<String, dynamic> m) => TodayAlarm(
    uid: uid,
    alarmAt: (m['alarmAt'] as Timestamp?)?.toDate(),
    graceMins: (m['graceMins'] as int?) ?? 10,
    snoozeCount: (m['snoozeCount'] as int?) ?? 0,
    snoozing: (m['snoozing'] as bool?) ?? false,
    wakeAt: (m['wakeAt'] as Timestamp?)?.toDate(),
  );
}


WakeCellStatus computeStatus({
  required DateTime now,
  TodayAlarm? alarm,
  GridPost? post,
}) {
  if (post != null) return WakeCellStatus.posted;
  if (alarm == null || alarm.alarmAt == null) return WakeCellStatus.noAlarm;

  final due = alarm.alarmAt!;
  final graceEnd = due.add(Duration(minutes: alarm.graceMins));
  if (alarm.snoozing) return WakeCellStatus.snoozing;
  if (now.isBefore(due)) return WakeCellStatus.waiting;
  if (now.isBefore(graceEnd)) return WakeCellStatus.due;
  return WakeCellStatus.lateSuspicious;
}
