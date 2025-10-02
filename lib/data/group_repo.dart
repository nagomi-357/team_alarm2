//(必要)data/group_repo.dart(グループ・投稿・アラーム)
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
class GroupRepo {
  final _db = FirebaseFirestore.instance;

  Stream<List<Map<String, dynamic>>> groupsByIds(List<String> ids) {
    // 10件制限があるため呼び出し側で分割推奨。MVPは単発取得でOK
    return _db
        .collection('groups')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .map((qs) => qs.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<Map<String, dynamic>?> groupDoc(String groupId) =>
      _db.collection('groups').doc(groupId).snapshots().map((d) => d.data());

  Stream<Map<String, Map<String, dynamic>>> todayAlarms(String groupId) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('todayAlarms')
          .snapshots()
          .map((qs) => { for (final d in qs.docs) d.id: d.data()});

  Stream<Map<String, Map<String, dynamic>>> gridPosts(String groupId) =>
      _db.collection('groups').doc(groupId).collection('gridPosts').snapshots()
          .map((qs) => { for (final d in qs.docs) d.id: d.data()});

  /// profiles 集合から指定した uid のプロフィール情報を取得する
  Stream<Map<String, Map<String, dynamic>>> profilesStream(List<String> uids) {
    if (uids.isEmpty) return const Stream.empty();
    return _db
        .collection('profiles')
        .where(FieldPath.documentId, whereIn: uids)
        .snapshots()
        .map((qs) => {for (final d in qs.docs) d.id: d.data()});
  }


  Future<String> createGroup(
      {required String name, required String ownerUid, String? avatarUrl}) async {
    final ref = _db.collection('groups').doc();
    await ref.set({
      'name': name,
      'avatar': avatarUrl,
      'members': [ownerUid],
      'admins': [ownerUid],
      'settings': {
        'graceMins': 10,
        'snoozeStepMins': 5,
        'snoozeWarnThreshold': 2
      },
      'gridActiveSince': FieldValue.serverTimestamp(),
      'gridExpiresAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('users').doc(ownerUid).set({
      'groups': FieldValue.arrayUnion([ref.id])
    }, SetOptions(merge: true));
    return ref.id;
  }

  /// 再設定時：起床時刻をクリアし、当日の投稿も削除（写真があれば Storage からも削除）
  Future<void> clearWakeAndPost({
    required String groupId,
    required String uid,
  }) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final alarmRef = groupRef.collection('todayAlarms').doc(uid);
    final postRef  = groupRef.collection('gridPosts').doc(uid);

    // 写真URL取得のために投稿ドキュメントを読む
    final snap = await postRef.get();
    final data = snap.data();
    final String? photoUrl = data != null ? (data['photoUrl'] as String?) : null;

    // Firestore: wakeAt を削除 + 投稿ドキュメント削除 をバッチで
    final batch = _db.batch();
    batch.set(alarmRef, {'wakeAt': FieldValue.delete()}, SetOptions(merge: true));
    batch.delete(postRef);
    await batch.commit();

    // Storage: 写真があれば実ファイルも削除（失敗してもアプリは継続）
    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        final ref = FirebaseStorage.instance.refFromURL(photoUrl);
        await ref.delete();
      } catch (_) {
        // ログ仕込みたい場合は print などに置き換え
      }
    }
  }


  Future<void> setTodayAlarm({
    required String groupId,
    required String uid,
    required DateTime wakeAt,
    required int snoozeStepMins,
    required int graceMins,
  }) async {
    await _db.collection('groups').doc(groupId).collection('todayAlarms').doc(
        uid).set({
      'wakeAt': Timestamp.fromDate(wakeAt),
      'snoozeStepMins': snoozeStepMins,
      'graceMins': graceMins,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // 目標再設定時に起床時刻をリセット（削除）
  Future<void> clearWakeAt({
    required String groupId,
    required String uid,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('todayAlarms')
        .doc(uid)
        .set({
      'wakeAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }


  Future<void> setWakeAt({
    required String groupId,
    required String uid,
    required DateTime wakeAt,
  }) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('todayAlarms')
          .doc(uid)
          .set({
        'wakeAt': Timestamp.fromDate(wakeAt),
      }, SetOptions(merge: true));


  Future<void> incrementSnooze(String groupId, String uid, int stepMins) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('todayAlarms')
          .doc(uid)
          .set({
        'snoozeCount': FieldValue.increment(1),
        'snoozing': true,
        'lastSnoozedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> clearSnoozing(String groupId, String uid) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('todayAlarms')
          .doc(uid)
          .set({
        'snoozing': false
      }, SetOptions(merge: true));

  Future<void> postOhayo(String groupId, String uid, {String? photoUrl}) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('gridPosts')
        .doc(uid)
        .set({
      'uid': uid,
      'type': photoUrl == null ? 'button' : 'photo',
      'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection('groups').doc(groupId).set({
      'lastActivityAt': FieldValue.serverTimestamp()
    }, SetOptions(merge: true));
  }

  Future<void> updateGroupBasics(String groupId,
      {String? name, String? avatarUrl}) async {
    await _db.collection('groups').doc(groupId).set({
      if (name != null) 'name': name,
      if (avatarUrl != null) 'avatar': avatarUrl,
      'lastActivityAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> manualReset(String groupId) async {
    final ref = _db.collection('groups').doc(groupId);
    final batch = _db.batch();

    final posts = await ref.collection('gridPosts').get();
    for (final d in posts.docs) {
      batch.delete(d.reference);
    }

    final alarms = await ref.collection('todayAlarms').get();
    for (final d in alarms.docs) {
      batch.delete(d.reference);
    }

    final timeline = await ref.collection('timeline').get();
    for (final d in timeline.docs) {
      batch.delete(d.reference);
    }

    await batch.commit();

    await ref.set({
      'gridActiveSince': FieldValue.serverTimestamp(),
      'gridExpiresAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DateTime> serverNow() async {
    final doc = _db.collection('_server').doc('_now');
    await doc.set({'t': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    final snap = await doc.get();
    return (snap.data()!['t'] as Timestamp).toDate();
  }


  Future<void> updateSettings(String groupId, {
    required int graceMins,
    required int snoozeStepMins,
    required int snoozeWarnThreshold,
    required int resetHour,
    required int resetMinute,
  }) {
    return _db.collection('groups').doc(groupId).set({
      'settings': {
        'graceMins': graceMins,
        'snoozeStepMins': snoozeStepMins,
        'snoozeWarnThreshold': snoozeWarnThreshold,
        'resetHour': resetHour,
        'resetMinute': resetMinute,
      }
    }, SetOptions(merge: true));
  }


  /// リセット境界（毎日）を超えていたら自動リセットする
  /// resetHour/resetMinute はローカル時刻基準で扱う
  Future<bool> ensureDailyResetIfNeeded(String groupId) async {
    final ref = _db.collection('groups').doc(groupId);
    final snap = await ref.get();
    final g = snap.data() ?? {};
    final settings = (g['settings'] as Map<String, dynamic>?) ?? {};
    final int rh = (settings['resetHour'] as int?) ?? 4;
    final int rm = (settings['resetMinute'] as int?) ?? 0;

    final Timestamp? sinceTs = g['gridActiveSince'] as Timestamp?;
    final DateTime since = (sinceTs?.toDate() ?? DateTime.now()).toLocal();

    DateTime boundaryFor(DateTime dt) {
      final b = DateTime(dt.year, dt.month, dt.day, rh, rm);
      if (dt.isBefore(b)) {
        return b.subtract(const Duration(days: 1));
      }
      return b;
    }

    final nowLocal = DateTime.now();
    final lastBoundary = boundaryFor(since);
    final curBoundary = boundaryFor(nowLocal);

    if (curBoundary.isAfter(lastBoundary)) {
      await manualReset(groupId); // 既存の手動リセットを再利用
      return true;
    }
    return false;
  }

// 目標時刻（アラームのターゲット）を保存
  Future<void> setAlarmAt({
    required String groupId,
    required String uid,
    required DateTime alarmAt,
  }) =>
      _db
          .collection('groups')
          .doc(groupId)
          .collection('todayAlarms')
          .doc(uid)
          .set({
        'alarmAt': Timestamp.fromDate(alarmAt),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

}