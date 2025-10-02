//（必要）data/timeline_repo.dart（タイムライン）

import 'package:cloud_firestore/cloud_firestore.dart';
import 'group_repo.dart';

class TimelineRepo {
  final _db = FirebaseFirestore.instance;

  Stream<List<Map<String, dynamic>>> timeline(String groupId, {int limit = 100}) {
    // タイムライン画面に直接来た場合でも、境界を跨いでいれば自動リセット
    Future.microtask(() => GroupRepo().ensureDailyResetIfNeeded(groupId));
    return _db
        .collection('groups').doc(groupId).collection('timeline')
        .orderBy('createdAt', descending: true).limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<void> log(String groupId, Map<String, dynamic> event) async {
    await _db.collection('groups').doc(groupId).collection('timeline').add({
      ...event, 'createdAt': FieldValue.serverTimestamp()
    });
    await _db.collection('groups').doc(groupId).set({
      'lastActivityAt': FieldValue.serverTimestamp()
    }, SetOptions(merge: true));
  }
}
