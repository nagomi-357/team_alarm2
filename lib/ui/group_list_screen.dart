//(必要)ui/group_list_screen.dart(複数グループ一覧)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/group_repo.dart';
import '../ui/group_grid_screen.dart';
import '../ui/invite/invite_screen.dart';
import '../data/storage_repo.dart';
import '../ui/pickers/image_pick.dart';
import '../ui/qr_scan_screen.dart';
import '../ui/profile/profile_screen.dart';
import 'package:team_alarm1_2/logic/invite_utils.dart';

class GroupListScreen extends StatelessWidget {
  final String myUid;
  final VoidCallback? onOpenProfile;

  const GroupListScreen({super.key, required this.myUid, this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(myUid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, snap) {
        final u = snap.data?.data() ?? {};
        final groupIds = List<String>.from(u['groups'] ?? const []);
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B0F12), Color(0xFF0E1B2A)],
            ),
          ),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('グループ', style: TextStyle(fontWeight: FontWeight.w700)),
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.white,
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B0F12), Color(0xFF0E1B2A)],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'カメラで読み取る',
                  onPressed: () async {
                    final raw = await Navigator.of(context).push<String?>(
                      MaterialPageRoute(builder: (_) => const QrScanScreen()),
                    );
                    if (raw == null || raw.isEmpty) return;

                    final code = InviteUtils.extractCode(raw);
                    if (code != null) {
                      // 新QR（?code=XXXX）で参加
                      final ok = await InviteUtils.joinByCode(
                        context: context, code: code, myUid: myUid,
                      );
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('グループに参加しました')),
                        );
                      }
                      return;
                    }

                    // ← ここから後方互換（旧QR）の救済
                    final token = InviteUtils.extractLegacyToken(raw);
                    if (token != null) {
                      // token で invites を検索する小関数をここで一時実装（ユーティリティ化でもOK）
                      final db = FirebaseFirestore.instance;
                      try {
                        final cg = await db
                            .collectionGroup('invites')
                            .where('token', isEqualTo: token) // ← 旧QR用
                            .limit(1)
                            .get();

                        if (cg.docs.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('無効なコードです（旧形式）')),
                            );
                          }
                          return;
                        }
                        final inviteRef = cg.docs.first.reference;
                        final groupId = inviteRef.parent.parent!.id;

                        await db.collection('groups').doc(groupId).update({
                          'members': FieldValue.arrayUnion([myUid]),
                        });
                        await db.collection('users').doc(myUid).set({
                          'groups': FieldValue.arrayUnion([groupId]),
                        }, SetOptions(merge: true));

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('グループに参加しました（旧QR）')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('参加に失敗しました: $e')),
                          );
                        }
                      }
                      return;
                    }

                    // どちらにも該当しない
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('このQRは招待コード形式ではありません（?code=XXXX が必要）')),
                      );
                    }
                  }
                  /*onPressed: () async {
                    final raw = await Navigator.of(context).push<String?>(
                      MaterialPageRoute(builder: (_) => const QrScanScreen()),
                    );
                    if (raw == null || raw.isEmpty) return;

                    // 抽出に失敗したら検索しない
                    final extracted = InviteUtils.extractCode(raw);
                    if (extracted == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('このQRは招待コード形式ではありません（?code=XXXX が必要）')),
                        );
                      }
                      return;
                    }

                    // 生成側が大文字英数字なので、念のため正規化
                    final code = extracted.trim().toUpperCase();

                    final ok = await InviteUtils.joinByCode(
                      context: context,
                      code: code,
                      myUid: myUid,
                    );
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('グループに参加しました')),
                      );
                    }
                  }*/,

                ),
                // Profile button with avatar
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
                  builder: (context, snapshot) {
                    final userData = snapshot.data?.data();
                    final String? photoUrl = userData != null
                        ? (userData['photoUrl'] as String?) ?? (userData['avatarUrl'] as String?)
                        : null;
                    return IconButton(
                      onPressed: onOpenProfile,
                      icon: photoUrl != null && photoUrl.isNotEmpty
                          ? CircleAvatar(
                              radius: 16,
                              backgroundImage: NetworkImage(photoUrl),
                              backgroundColor: Colors.transparent,
                            )
                          : const Icon(Icons.person),
                      tooltip: 'プロフィール',
                    );
                  },
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () async {
                final created = await _createGroupDialog(context);
                if (created == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('グループを作成しました')));
                }
              },
              backgroundColor: const Color(0xFF12171E),
              foregroundColor: const Color(0xFFBDEBFF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFF2B3C4B), width: 1),
              ),
              child: const Icon(Icons.add),
            ),
            backgroundColor: Colors.transparent,
            body: groupIds.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.groups_2_rounded, size: 72, color: Color(0xFF8DEBFF)),
                        SizedBox(height: 16),
                        Text(
                          '参加中のグループはありません。\n右下「＋」で作成、または招待から参加',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                        ),
                      ],
                    ),
                  )
                : _GroupList(myUid: myUid, groupIds: groupIds),
          ),
        );
      },
    );
  }


  Future<bool?> _createGroupDialog(BuildContext context) async {
    final nameCtl = TextEditingController();
    File? iconFile;
    final store = StorageRepo();
    final repo = GroupRepo();

    return showDialog<bool>(
      context: context,
      builder: (_) =>
          StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF12171E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              contentTextStyle: const TextStyle(color: Colors.white70),
              title: const Text('新しいグループ'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () async {
                    final f = await ImagePick.pickFromGallery();
                    if (f != null) setState(() => iconFile = f);
                  },
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFF0E1B2A),
                    backgroundImage: iconFile != null ? FileImage(iconFile!) : null,
                    child: iconFile == null ? const Icon(Icons.group, color: Color(0xFFBDEBFF)) : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'グループ名',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2B3C4B))),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF66D6E3))),
                    filled: true,
                    fillColor: Color(0xFF0F141B),
                  ),
                ),
              ]),
              actions: [

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF173248),
                    foregroundColor: const Color(0xFFDBF7FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final name = nameCtl.text
                        .trim()
                        .isEmpty ? 'グループ' : nameCtl.text.trim();
                    // まず作成
                    final gid = await repo.createGroup(
                        name: name, ownerUid: myUid);
                    // アイコンがあればアップロードして反映
                    if (iconFile != null) {
                      final url = await store.uploadGroupIcon(
                          groupId: gid, file: iconFile!);
                      await repo.updateGroupBasics(gid, avatarUrl: url);
                    }
                    if (context.mounted) Navigator.pop(context, true);
                  }, child: const Text('作成')),
              ],
            );
          }),
    );
  }


  Future<String?> _input(BuildContext context, String title) async {
    final c = TextEditingController();
    return showDialog<String>(context: context, builder: (_) =>
        AlertDialog(
          title: Text(title),
          content: TextField(controller: c, autofocus: true),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context, c.text),
                child: const Text('作成'))
          ],
        ));
  }
}

class _GroupList extends StatelessWidget {
  final String myUid; final List<String> groupIds;
  const _GroupList({required this.myUid, required this.groupIds});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('groups')
          .where(FieldPath.documentId, whereIn: groupIds.take(10).toList())
          .snapshots(),
      builder: (context, snap) {
        final docs = List.of(snap.data?.docs ?? const []);
        docs.sort((a,b){
          final A=(a.data()['lastActivityAt'] as Timestamp?)?.toDate();
          final B=(b.data()['lastActivityAt'] as Timestamp?)?.toDate();
          return (B??DateTime(0)).compareTo(A??DateTime(0));
        });
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final d = docs[i]; final g = d.data();
            final name = (g['name'] as String?) ?? 'グループ';
            final members = List<String>.from((g['members'] as List?) ?? const []);
            final subtitle = 'メンバー ${members.length} 人';
            final String? avatarUrl = (g['avatar'] as String?) ?? (g['avatarUrl'] as String?);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF12171E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2B3C4B), width: 1),
                boxShadow: const [
                  BoxShadow(color: Color(0x3312D6DF), blurRadius: 12, offset: Offset(0, 6)),
                ],
              ),
              child: ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF173248), Color(0xFF0E1B2A)]),
                    border: Border.all(color: const Color(0xFF3D90A1), width: 1),
                  ),
                  child: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? ClipOval(
                          child: Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            width: 44,
                            height: 44,
                          ),
                        )
                      : const Center(child: Icon(Icons.group, color: Color(0xFFBDEBFF))),
                ),
                title: Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupGridScreen(
                      groupId: d.id,
                      myUid: myUid,
                      memberUids: members,
                      availableGroups: const [],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
