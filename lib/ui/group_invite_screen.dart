import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class GroupInviteScreen extends StatelessWidget {
  final String groupId;
  const GroupInviteScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('groups').doc(groupId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() ?? {};
        final code = data['inviteCode'] as String? ?? '';
        return Scaffold(
          appBar: AppBar(title: const Text('招待コード')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SelectableText(code, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 16),
                if (code.isNotEmpty) QrImageView(data: code, size: 200),
              ],
            ),
          ),
        );
      },
    );
  }
}
