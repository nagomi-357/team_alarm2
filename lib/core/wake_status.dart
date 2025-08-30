//状態判断
enum WakeCellStatus { noAlarm, waiting, due, lateSuspicious, posted }

class TodayAlarm {
  final String uid;
  final DateTime? alarmAt;
  final int graceMins;
  TodayAlarm({required this.uid, required this.alarmAt, required this.graceMins});
  factory TodayAlarm.fromMap(String uid, Map<String, dynamic> m) => TodayAlarm(
    uid: uid,
    alarmAt: (m['alarmAt'] as Timestamp?)?.toDate(),
    graceMins: (m['graceMins'] as int?) ?? 10,
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

  final due = alarm.alarmAt!;
  final graceEnd = due.add(Duration(minutes: alarm.graceMins));
  if (now.isBefore(due)) return WakeCellStatus.waiting;
  if (now.isBefore(graceEnd)) return WakeCellStatus.due;
  return WakeCellStatus.lateSuspicious;
}
