// models/group_calemnder_event.dart


import 'package:cloud_firestore/cloud_firestore.dart';

class GroupCalendarEvent {
  final String id;
  final DateTime date;
  final DateTime alarmDateTime;
  final List<String> groupIds;
  final String createdByGroupId;
  final String createdByUid;
  final String dateKey;

  const GroupCalendarEvent({
    required this.id,
    required this.date,
    required this.alarmDateTime,
    required this.groupIds,
    required this.createdByGroupId,
    required this.createdByUid,
    required this.dateKey,
  });

  factory GroupCalendarEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final dateTs = data['date'] as Timestamp?;
    final alarmTs = data['alarmDateTime'] as Timestamp?;
    final groupIds = List<String>.from((data['groupIds'] as List?) ?? const []);
    final createdByGroupId = (data['createdByGroupId'] as String?) ?? '';
    final createdByUid = (data['createdByUid'] as String?) ?? '';
    final dateKey = (data['dateKey'] as String?) ?? '';

    return GroupCalendarEvent(
      id: doc.id,
      date: dateTs?.toDate() ?? DateTime.now(),
      alarmDateTime: alarmTs?.toDate() ?? DateTime.now(),
      groupIds: groupIds,
      createdByGroupId: createdByGroupId,
      createdByUid: createdByUid,
      dateKey: dateKey,
    );
  }
}