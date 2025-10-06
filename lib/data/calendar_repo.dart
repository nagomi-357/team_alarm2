//data/calender_repo/dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/group_calendar_event.dart';

class CalendarRepo {
  final _db = FirebaseFirestore.instance;

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Stream<List<GroupCalendarEvent>> eventsForGroup(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('calendarEvents')
        .orderBy('alarmDateTime')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(GroupCalendarEvent.fromDoc).toList());
  }

  Stream<List<GroupCalendarEvent>> eventsForGroupOnDate(String groupId, DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final key = _dateKey(normalized);
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('calendarEvents')
        .where('dateKey', isEqualTo: key)
        .orderBy('alarmDateTime')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(GroupCalendarEvent.fromDoc).toList());
  }

  Future<void> saveEvent({
    required DateTime date,
    required TimeOfDay timeOfDay,
    required List<String> groupIds,
    required String createdByGroupId,
    required String createdByUid,
  }) async {
    if (groupIds.isEmpty) {
      throw ArgumentError('At least one group must be selected');
    }

    final normalized = DateTime(date.year, date.month, date.day);
    final alarmDateTime = DateTime(date.year, date.month, date.day, timeOfDay.hour, timeOfDay.minute);
    final key = _dateKey(normalized);
    final eventId = '${key}_${DateTime.now().millisecondsSinceEpoch}_${createdByUid.hashCode}';

    final data = <String, dynamic>{
      'date': Timestamp.fromDate(normalized),
      'dateKey': key,
      'alarmDateTime': Timestamp.fromDate(alarmDateTime),
      'groupIds': groupIds,
      'createdByGroupId': createdByGroupId,
      'createdByUid': createdByUid,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    for (final groupId in groupIds) {
      final docRef = _db.collection('groups').doc(groupId).collection('calendarEvents').doc(eventId);
      batch.set(docRef, data, SetOptions(merge: true));
    }
    await batch.commit();
  }
}