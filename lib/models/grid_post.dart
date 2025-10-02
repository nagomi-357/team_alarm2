// lib/models/grid_post.dart
import 'package:cloud_firestore/cloud_firestore.dart';


class GridPost {
  final String uid;
  final String? type;
  final String? text;
  final String? photoUrl;
  final DateTime? createdAt;

  GridPost({
    required this.uid,
    this.type,
    this.text,
    this.photoUrl,
    this.createdAt,
  });

  factory GridPost.fromMap(String uid, Map<String, dynamic> m) => GridPost(
    uid: uid,
    type: m['type'] as String?,
    text: m['text'] as String?,
    photoUrl: m['photoUrl'] as String?,
    createdAt: _toDateTime(m['createdAt']),
  );

  Map<String, dynamic> toMap() => {
    if (type != null) 'type': type,
    if (text != null) 'text': text,
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
  };

  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    return null;
  }
}
