//data/storage_repo.dart(画像アップロード)

import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

class StorageRepo {
  final _storage = FirebaseStorage.instance;

  Future<String> uploadGroupTodayPhoto({
    required String groupId, required String uid, required File file,
  }) async {
    final now = DateTime.now();
    final ymd = DateFormat('yyyyMMdd').format(now);
    final ts  = DateFormat('HHmmssSSS').format(now);
    final ref = _storage.ref().child('groups/$groupId/today/$uid/$ymd-$ts.jpg');
    final meta = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'public,max-age=300,immutable',
      customMetadata: {'groupId': groupId, 'uid': uid, 'expiresHint': '24h'},
    );
    final task = await ref.putFile(file, meta);
    return await task.ref.getDownloadURL();
  }
}
