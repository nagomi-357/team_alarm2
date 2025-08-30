//data/chat_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRepo {
  final _db = FirebaseFirestore.instance;
  Stream<List<Map<String, dynamic>>> chats(String groupId, {int limit = 200}) =>
      _db.collection('groups').doc(groupId).collection('chats')
          .orderBy('createdAt', descending: true).limit(limit)
          .snapshots().map((qs) => qs.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Future<void> sendText(String groupId, String uid, String text) =>
      _db.collection('groups').doc(groupId).collection('chats').add({
        'type': 'text', 'senderUid': uid, 'text': text, 'createdAt': FieldValue.serverTimestamp(),
      });
}

