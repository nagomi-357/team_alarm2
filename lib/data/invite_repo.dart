// lib/data/invite_repo.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class InviteRepo {
  final _db = FirebaseFirestore.instance;

  String generateCode({int len = 8}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<Map<String, dynamic>> createInvite(
      String groupId,
      String adminUid, {
        int maxUses = 1,
        Duration ttl = const Duration(hours: 24),
      }) async {
    final id = _db.collection('groups').doc().id;
    final code = generateCode();
    final token = _db.collection('_t').doc().id + _db.collection('_t').doc().id;
    final ref = _db.collection('groups').doc(groupId).collection('invites').doc(id);
    final expiresAt = DateTime.now().add(ttl);
    await ref.set({
      'code': code,
      'token': token,
      'type': 'single',
      'maxUses': maxUses,
      'usedCount': 0,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdBy': adminUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return {
      'inviteId': id,
      'code': code,
      'token': token,
      'expiresAt': expiresAt,
    };
  }
}


