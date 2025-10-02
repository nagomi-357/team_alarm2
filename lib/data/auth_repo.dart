//data/auth_repo.dart(匿名認証)

import 'package:firebase_auth/firebase_auth.dart';

class AuthRepo {
  static Future<void> ensureSignedInAnon() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }
}
