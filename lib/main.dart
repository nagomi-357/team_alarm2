import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'ui/group_list_screen.dart';
import 'notifications/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();
  runApp(const MyApp());
}

const demoMyUid = 'user_a';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WakeGrid',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const GroupListScreen(myUid: demoMyUid),
    );
  }
}
