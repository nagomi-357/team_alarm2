// ui/group_invite_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:team_alarm1_2/logic/invite_utils.dart';
// ← スキャン画面の import は不要に
// import 'package:team_alarm1_2/ui/qr_scan_screen.dart';

// （任意）共通ユーティリティを作っている場合は下を使う
// import 'package:team_alarm1_2/logic/invite_utils.dart';

class GroupInviteScreen extends StatefulWidget {
  const GroupInviteScreen({super.key});
  @override
  State<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends State<GroupInviteScreen> {
  String? _selectedGroupId;
  String? _inviteCode;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('招待QR'),
        backgroundColor: Colors.brown.shade800,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      backgroundColor: Colors.brown.shade300,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGroupPicker(context),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (_selectedGroupId == null || _creating)
                  ? null
                  : () => _ensureInviteAndShow(context),
              icon: const Icon(Icons.qr_code_2),
              label: _creating
                  ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('招待QRを生成/表示'),
            ),
            const SizedBox(height: 24),
            if (_inviteCode != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrImageView(
                        data: InviteUtils.buildInviteUrl(_inviteCode!), // ← ?code=XXXX に統一
                        version: QrVersions.auto,
                        size: 240,
                        gapless: false,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(InviteUtils.buildInviteUrl(_inviteCode!)),
                      const SizedBox(height: 8),
                      Text('コード: ${_inviteCode!}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 自分の所属グループからQRを出す対象を選ぶ
  Widget _buildGroupPicker(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('未ログインです'));
    }
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = List<String>.from((snap.data!.data() as Map<String, dynamic>?)?['groups'] ?? const []);
        if (groups.isEmpty) {
          return const Text('所属グループがありません。まずはグループを作成・参加してください。');
        }
        _selectedGroupId ??= groups.first;
        return DropdownButtonFormField<String>(
          value: _selectedGroupId,
          items: groups.map((g) => DropdownMenuItem(value: g, child: Text('Group: $g'))).toList(),
          onChanged: (v) => setState(() { _selectedGroupId = v; _inviteCode = null; }),
          decoration: const InputDecoration(
            labelText: 'QRを表示するグループ',
            border: OutlineInputBorder(),
          ),
        );
      },
    );
  }

  // --- 招待コードの生成/取得（既存ロジックを踏襲）
  Future<void> _ensureInviteAndShow(BuildContext context) async {
    final gid = _selectedGroupId;
    if (gid == null) return;
    setState(() => _creating = true);
    try {
      final db = FirebaseFirestore.instance;
      // 既存の招待(最新1件)を探す
      final q = await db.collection('groups').doc(gid)
          .collection('invites').orderBy('createdAt', descending: true).limit(1).get();

      if (q.docs.isNotEmpty) {
        _inviteCode = q.docs.first.data()['code'] as String?;
      } else {
        // 新規作成（短い英数字コード）
        final code = _randomCode(8);
        await db.collection('groups').doc(gid).collection('invites').add({
          'code': code,
          'createdAt': FieldValue.serverTimestamp(),
          'expireAt': null,
          'usageLimit': null,
        });
        _inviteCode = code;
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _randomCode(int len) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }


}