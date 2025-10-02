//lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'data/auth_repo.dart';
import 'data/user_repo.dart';
import 'ui/group_list_screen.dart';
import 'ui/profile/profile_screen.dart';
import 'ui/invite/qr_join_screen.dart';
import 'notifications/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();
  // 匿名ログイン
  await AuthRepo.ensureSignedInAnon();

  runApp(const RootApp());

  Future.delayed(const Duration(seconds: 3), () async {
    await NotificationService.instance.showNowTest();
  });
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WakeGrid',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      onGenerateRoute: (settings) {
        if (settings.name?.startsWith('/join') == true && settings.arguments is Uri) {
          return MaterialPageRoute(builder: (_) => QRJoinScreen(uri: settings.arguments as Uri));
        }
        return null;
      },
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget { const _Root({super.key}); @override State<_Root> createState() => _RootState(); }
class _RootState extends State<_Root> {
  StreamSubscription? _sub;
  @override
  void initState() {
    super.initState();
    // ディープリンク（wakegrid://join?...）を受け取る場合は、必要に応じてuni_linksなど導入
  }
  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return GroupListScreen(myUid: uid,
      onOpenProfile: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(myUid: uid))),
    );
  }
}
