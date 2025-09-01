//data/group_repo.dart(Firebase操作)
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupRepo {
  final _db = FirebaseFirestore.instance;

  Future<DateTime> serverNow() async {
    await _db.collection('_server').doc('_now').set({'t': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    final doc = await _db.collection('_server').doc('_now').get();
    return (doc.data()!['t'] as Timestamp).toDate();
  }

  Stream<Map<String, dynamic>> groupDocStream(String groupId) =>
      _db.collection('groups').doc(groupId).snapshots().map((d) => d.data() ?? {});

  Stream<Map<String, Map<String, dynamic>>> todayAlarmsStream(String groupId) =>
      _db.collection('groups').doc(groupId).collection('todayAlarms').snapshots()
          .map((qs) => { for (final d in qs.docs) d.id : d.data() });

  Stream<Map<String, Map<String, dynamic>>> gridPostsStream(String groupId) =>
      _db.collection('groups').doc(groupId).collection('gridPosts').snapshots()
          .map((qs) => { for (final d in qs.docs) d.id : d.data() });

  Future<void> postOhayo(String groupId, String uid, {String? text}) =>
      _db.collection('groups').doc(groupId).collection('gridPosts').doc(uid).set({
        'type': 'button', if (text != null) 'text': text,
        'createdAt': FieldValue.serverTimestamp(), 'uid': uid,
      }, SetOptions(merge: true));

  Future<void> attachPhoto(String groupId, String uid, {required String photoUrl, String? text}) =>
      _db.collection('groups').doc(groupId).collection('gridPosts').doc(uid).set({
        'type': 'photo', 'photoUrl': photoUrl, if (text != null) 'text': text,
        'createdAt': FieldValue.serverTimestamp(), 'uid': uid,
      }, SetOptions(merge: true));

  Future<void> setTodayAlarm(String groupId, String uid, {required DateTime alarmAt, int graceMins = 10}) =>
      _db.collection('groups').doc(groupId).collection('todayAlarms').doc(uid).set({
        'uid': uid, 'alarmAt': Timestamp.fromDate(alarmAt),
        'graceMins': graceMins, 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> incrementSnooze(String groupId, String uid, {int stepMins = 5}) =>
      _db.collection('groups').doc(groupId).collection('todayAlarms').doc(uid).set({
        'uid': uid, 'snoozeMins': stepMins, 'snoozeCount': FieldValue.increment(1),
        'lastSnoozedAt': FieldValue.serverTimestamp(), 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> manualReset(String groupId) async {
    final gref = _db.collection('groups').doc(groupId);
    final posts = await gref.collection('gridPosts').get();
    final batch = _db.batch();
    for (final d in posts.docs) { batch.delete(d.reference); }
    await batch.commit();
    await gref.set({
      'gridActiveSince': FieldValue.serverTimestamp(),
      'gridExpiresAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendWakeNudge(String groupId, {required String targetUid, required String senderUid}) =>
      _db.collection('groups').doc(groupId).collection('nudges').doc().set({
        'type': 'wake', 'targetUid': targetUid, 'senderUid': senderUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateGroupSettings(String groupId, {
    int? graceMins, int? snoozeStepMins, int? snoozeWarnThreshold,
  }) =>
      _db.collection('groups').doc(groupId).set({
        'settings': {
          if (graceMins != null) 'graceMins': graceMins,
          if (snoozeStepMins != null) 'snoozeStepMins': snoozeStepMins,
          if (snoozeWarnThreshold != null) 'snoozeWarnThreshold': snoozeWarnThreshold,
        }
      }, SetOptions(merge: true));
  Future<String> createGroup(String name, String ownerUid) async {
    final doc = _db.collection('groups').doc();
    final code = (Random().nextInt(900000) + 100000).toString();
    await doc.set({
      'name': name,
      'members': [ownerUid],
      'admins': [ownerUid],
      'inviteCode': code,
      'gridActiveSince': FieldValue.serverTimestamp(),
      'gridExpiresAt': FieldValue.serverTimestamp(),
      'settings': {'graceMins': 10, 'snoozeStepMins': 5, 'snoozeWarnThreshold': 2},
    });
    return doc.id;
  }

  Future<String?> joinGroupByCode(String code, String uid) async {
    final qs = await _db.collection('groups').where('inviteCode', isEqualTo: code).limit(1).get();
    if (qs.docs.isEmpty) return null;
    final ref = qs.docs.first.reference;
    await ref.update({'members': FieldValue.arrayUnion([uid])});
    return ref.id;
  }
}
