//(必要)ui/invite/invite_screen.dart（コード発行・表示）

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../data/invite_repo.dart';

class InviteScreen extends StatefulWidget {
  final String myUid;
  final String groupId; // ★ 必須
  const InviteScreen({super.key, required this.myUid, required this.groupId});

  @override State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  Map<String,dynamic>? invite;
  final repo = InviteRepo();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('メンバー招待'),
          backgroundColor: Colors.brown.shade800,
          foregroundColor: Theme.of(context).colorScheme.onPrimary),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (invite == null) FilledButton(
                onPressed: () async {
                  final inv = await repo.createInvite(widget.groupId, widget.myUid);
                  setState(()=> invite = inv);
                }, child: const Text('招待コードを発行')),
            if (invite != null) ...[
              Text('コード： ${invite!['code']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              QrImageView(
                data: 'wakegrid://join?gid=${widget.groupId}&t=${invite!['token']}',
                size: 220,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
