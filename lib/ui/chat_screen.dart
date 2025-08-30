//chat_screen.dart（簡易チャット）

import 'package:flutter/material.dart';
import '../data/chat_repo.dart';

class ChatScreen extends StatelessWidget {
  final String groupId; final String myUid;
  const ChatScreen({super.key, required this.groupId, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final repo = ChatRepo();
    return Scaffold(
      appBar: AppBar(title: const Text('チャット')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repo.chats(groupId),
        builder: (context, snap) {
          final items = snap.data ?? const [];
          return ListView.separated(
            reverse: true, padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[i];
              final type = (m['type'] as String?) ?? 'text';
              final isMe = m['senderUid'] == myUid;
              if (type == 'stamp_wake') {
                final sender = m['senderUid'] ?? '';
                final target = m['targetUid'] ?? '';
                return _WakeStamp(sender: sender, target: target);
              } else {
                return _Bubble(text: m['text'] ?? '', isMe: isMe);
              }
            },
            separatorBuilder: (_, __) => const SizedBox(height: 8),
          );
        },
      ),
      bottomNavigationBar: _Input(groupId: groupId, myUid: myUid),
    );
  }
}

class _WakeStamp extends StatelessWidget {
  final String sender, target;
  const _WakeStamp({required this.sender, required this.target});
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    Card(color: Colors.orange.shade100, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.notifications_active), const SizedBox(width: 8),
          Text('📣 $sender が $target を起こした！', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  ]);
}

class _Bubble extends StatelessWidget {
  final String text; final bool isMe;
  const _Bubble({required this.text, required this.isMe});
  @override
  Widget build(BuildContext context) {
    final bg = isMe ? Colors.blue.shade100 : Colors.grey.shade200;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Text(text)),
    );
  }
}

class _Input extends StatefulWidget {
  final String groupId, myUid;
  const _Input({required this.groupId, required this.myUid});
  @override State<_Input> createState() => _InputState();
}
class _InputState extends State<_Input> {
  final _c = TextEditingController(); final _repo = ChatRepo();
  @override
  Widget build(BuildContext context) => SafeArea(child:
  Row(children: [
    const SizedBox(width: 8),
    Expanded(child: TextField(controller: _c, decoration: const InputDecoration(hintText: 'メッセージを入力…'))),
    IconButton(icon: const Icon(Icons.send), onPressed: () async {
      final t = _c.text.trim(); if (t.isEmpty) return;
      await _repo.sendText(widget.groupId, widget.myUid, t); _c.clear();
    }),
  ]),
  );
}
