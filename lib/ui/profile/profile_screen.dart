//(必要)ui/profile/profile_screen.dart(プロフィール)
import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/user_repo.dart';
import '../../data/storage_repo.dart';
import '../pickers/image_pick.dart';

class ProfileScreen extends StatefulWidget {
  final String myUid; const ProfileScreen({super.key, required this.myUid});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
  final _repo = UserRepo();
  final _store = StorageRepo();
  final _name = TextEditingController();
  File? _iconFile; String? _iconUrl;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _repo.userDocStream(widget.myUid),
      builder: (context, snap) {
        final u = snap.data ?? {};
        _name.text = _name.text.isEmpty ? (u['displayName'] ?? '') : _name.text;
        _iconUrl = _iconUrl ?? u['photoUrl'];

        return Scaffold(
          appBar: AppBar(title: const Text('プロフィール'),
              backgroundColor: Colors.brown.shade800,
              foregroundColor: Theme.of(context).colorScheme.onPrimary),
            backgroundColor: Colors.brown.shade300,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              GestureDetector(
                onTap: () async {
                  final f = await ImagePick.pickFromGallery();
                  if (f != null) setState(()=> _iconFile = f);
                },
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: (_iconUrl != null) ? NetworkImage(_iconUrl!) : null,
                  child: (_iconUrl == null)
                      ? const Icon(Icons.person, size: 40)
                      : null,
                )
              ),

              TextButton.icon(
                icon: const Icon(Icons.photo),
                label: const Text('プロフィール画像を変更'),
                onPressed: () async {
                  final f = await ImagePick.pickFromGallery();
                  if (f != null) setState(()=> _iconFile = f);
                },
              ),

              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'ユーザー名')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  String? url = _iconUrl;
                  if (_iconFile != null) {
                    url = await _store.uploadUserIcon(uid: widget.myUid, file: _iconFile!);
                  }
                  await _repo.upsertProfile(widget.myUid,
                      displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
                      photoUrl: url);
                  if (mounted) Navigator.pop(context); // ★ 自動でグループ一覧へ戻る
                },
                child: const Text('保存'),
              ),
            ]),
          ),
        );
      },
    );
  }

}



