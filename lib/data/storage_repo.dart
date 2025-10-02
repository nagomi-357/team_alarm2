//(必要)data/storage_repo.dart(画像アップロード)
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../ui/pickers/image_pick.dart';

class StorageRepo {
  final _s = FirebaseStorage.instance;

  Future<String> uploadGroupPhoto({required String groupId, required String uid, required File file}) async {
    final now = DateTime.now();
    final ymd = DateFormat('yyyyMMdd').format(now);
    final ts  = DateFormat('HHmmssSSS').format(now);
    final ref = _s.ref('groups/$groupId/today/$uid/$ymd-$ts.jpg');
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }

  /// 成功なら downloadURL、キャンセルなら null を返す。
  Future<String?> pickAndUploadUserIcon({required String uid}) async {
    final file = await ImagePick.pickFromGallery(); // 既存のユーティリティ
    if (file == null) return null;
    return uploadUserIcon(uid: uid, file: file);
  }

  // ★ 追加：ユーザーアイコン
  Future<String> uploadUserIcon({required String uid, required File file}) async {
    final ref = _s.ref('users/$uid/icon.jpg');
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }

  // ★ 追加：グループアイコン
  Future<String> uploadGroupIcon({required String groupId, required File file}) async {
    final ref = _s.ref('groups/$groupId/icon.jpg');
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }
}
