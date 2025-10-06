//models/group_summary.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class GroupSummary {
  final String id;
  final String name;
  final List<String> memberUids;

  const GroupSummary({
    required this.id,
    required this.name,
    required this.memberUids,
  });

  factory GroupSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final members = List<String>.from((data['members'] as List?) ?? const []);
    final name = (data['name'] as String?) ?? 'グループ';
    return GroupSummary(id: doc.id, name: name, memberUids: members);
  }
}