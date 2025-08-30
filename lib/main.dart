import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'ui/group_grid_screen.dart';
import 'ui/chat_screen.dart';
import 'ui/group_settings_screen.dart';
import 'notifications/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();
  runApp(const MyApp());
}

// ★ デモ用：任意のユーザーIDを固定（本番はFirebase Authを入れてください）
const demoMyUid = 'user_a';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WakeGrid',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const DemoHome(),
      routes: {
        '/chat': (_) => const SizedBox(),
        '/settings': (_) => const SizedBox(),
      },
    );
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});
  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  String? groupId;
  List<String> members = const ['user_a','user_b','user_c'];

  @override
  void initState() {
    super.initState();
    _ensureDemoGroup();
  }

  Future<void> _ensureDemoGroup() async {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('groups').doc('demo_group');
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'name': 'デモグループ',
        'members': members,
        'admins': ['user_a'],
        'gridActiveSince': FieldValue.serverTimestamp(),
        'gridExpiresAt': FieldValue.serverTimestamp(),
        'settings': {'graceMins': 10, 'snoozeStepMins': 5, 'snoozeWarnThreshold': 2},
      });
    }
    setState(() => groupId = 'demo_group');
  }

  @override
  Widget build(BuildContext context) {
    if (groupId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return GroupGridScreen(groupId: groupId!, memberUids: members, myUid: demoMyUid);
  }
}
