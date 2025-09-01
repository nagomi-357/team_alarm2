import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/group_repo.dart';
import 'group_grid_screen.dart';
import 'qr_scan_screen.dart';

class GroupListScreen extends StatelessWidget {
  final String myUid;
  const GroupListScreen({super.key, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final qs = FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: myUid)
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('グループ一覧')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: qs,
        builder: (_, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('グループがありません'));
          }
          return ListView(
            children: [
              for (final d in docs)
                ListTile(
                  title: Text(d.data()['name'] ?? d.id),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupGridScreen(groupId: d.id, myUid: myUid),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'create',
            onPressed: () => _createGroup(context),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'join',
            onPressed: () => _joinGroup(context),
            child: const Icon(Icons.group_add),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroup(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('グループ作成'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: '名前'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('作成')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = GroupRepo();
    final gid = await repo.createGroup(c.text.isEmpty ? '新しいグループ' : c.text, myUid);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupGridScreen(groupId: gid, myUid: myUid)),
    );
  }

  Future<void> _joinGroup(BuildContext context) async {
    String? code = await showDialog<String>(
      context: context,
      builder: (_) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('グループに参加'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: '招待コード'),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final scanned = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => const QrScanScreen()),
                );
                Navigator.pop(context, scanned);
              },
              child: const Text('QRスキャン'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('参加')),
          ],
        );
      },
    );
    if (code == null || code.isEmpty) return;
    final repo = GroupRepo();
    final gid = await repo.joinGroupByCode(code, myUid);
    if (!context.mounted) return;
    if (gid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('グループが見つかりません')));
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupGridScreen(groupId: gid, myUid: myUid)),
      );
    }
  }
}
