import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class UserRepo {
  final _db = FirebaseFirestore.instance;
  final col = FirebaseFirestore.instance.collection('users');

  Stream<Map<String, dynamic>?> userDocStream(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((d) => d.data());

  Future<void> upsertProfile(String uid, {String? displayName, String? photoUrl}) =>
      _db.collection('users').doc(uid).set({
        if (displayName != null) 'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
      }, SetOptions(merge: true));


  Future<void> setSleepLocked({
    required String uid,
    required bool locked,
    String? groupId,
  }) async {
    final data = <String, dynamic>{
      'sleepLocked': locked,
      'sleepLockGroupId': locked ? groupId : null,
    };
    await col.doc(uid).set(data, SetOptions(merge: true));
  }
  // ★ 追加： 10件制限に合わせて分割購読してマージ
  // lib/data/user_repo.dart 内

  Stream<Map<String, Map<String, dynamic>>> profilesByUids(List<String> uids) {
    // Firestore の whereIn は最大10件なので分割
    final chunks = <List<String>>[];
    for (var i = 0; i < uids.length; i += 10) {
      chunks.add(uids.sublist(i, (i + 10 > uids.length) ? uids.length : i + 10));
    }

    // チャンクごとの最新スナップショットを保持し、更新のたびに結合して流す
    final latest = List<Map<String, Map<String, dynamic>>?>.filled(chunks.length, null);
    final subs = <StreamSubscription>[];
    final controller = StreamController<Map<String, Map<String, dynamic>>>.broadcast();

    void emitMerged() {
      final merged = <String, Map<String, dynamic>>{};
      for (final part in latest) {
        if (part != null) merged.addAll(part);
      }
      // 1人もいない場合も空Mapを流す（UI側でnullチェック不要にする）
      controller.add(merged);
    }

    void start() {
      if (chunks.isEmpty) {
        // メンバー0人でも空Mapを出して完了
        controller.add(const {});
        return;
      }
      for (var i = 0; i < chunks.length; i++) {
        final idx = i;
        final query = _db.collection('users').where(FieldPath.documentId, whereIn: chunks[i]);
        final sub = query.snapshots().listen((qs) {
          final map = <String, Map<String, dynamic>>{};
          for (final d in qs.docs) {
            map[d.id] = d.data();
          }
          latest[idx] = map;
          emitMerged();
        }, onError: controller.addError);
        subs.add(sub);
      }
    }

    controller
      ..onListen = start
      ..onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };

    return controller.stream;
  }

}

