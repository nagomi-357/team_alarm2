//(必要)ui/invite/qr_join_screen.dart（QR/リンクで参加）

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../group_grid_screen.dart';

class QRJoinScreen extends StatelessWidget {
  final Uri uri;
  const QRJoinScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('グループに参加')),
      body: FutureBuilder(
        future: _joinAndFetch(context),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final msg = (s.data == true) ? '参加しました' : '無効な招待リンクです';
          return Center(child: Text(msg));
        },
      ),
    );
  }

  Future<bool> _joinAndFetch(BuildContext context) async {
    final gid = uri.queryParameters['gid'];
    final token = uri.queryParameters['t']; // ★ MVPでは未検証（本番は Functions で検証）
    if (gid == null || token == null) return false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final db = FirebaseFirestore.instance;
    // 参加（MVP：直接更新。実運用は Functions を推奨）
    await db.collection('groups').doc(gid)
        .update({'members': FieldValue.arrayUnion([uid])});
    await db.collection('users').doc(uid)
        .set({'groups': FieldValue.arrayUnion([gid])}, SetOptions(merge: true));

    // グループ情報を取得してグリッドへ遷移（memberUids が必要）
    final gdoc = await db.collection('groups').doc(gid).get();
    final members = List<String>.from((gdoc.data()?['members'] as List?) ?? const []);

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupGridScreen(
            groupId: gid,
            myUid: uid,
            memberUids: members,
            availableGroups: const [], // pass empty summaries to satisfy required param
          ),
        ),
      );
    }
    return true;
  }
}
