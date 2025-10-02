// lib/logic/invite_utils.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InviteUtils {
  /// QRに埋め込むURL（?code=XXXX に統一）
  static String buildInviteUrl(String code) {
    return 'wakegrid://join?code=$code';
    // https を使う場合は下でもOK:
    // return 'https://team-alarm.app/invite?code=$code';
  }

  /// RAW文字列から招待コード(code)のみを抽出
  /// RAW文字列から招待コード(code)のみを抽出
  static String? extractCode(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      // まずは新フォーマット ?code=XXXX を最優先
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) return code.trim().toUpperCase();
    }
    // 素の英数字コード（6〜64桁）はそのまま許容
    final reg = RegExp(r'^[A-Za-z0-9]{6,64}$');
    if (reg.hasMatch(raw)) return raw.trim().toUpperCase();
    return null;  // ← ここで null を返すのは「code としては不適」
  }

  /// 旧フォーマット（?t=TOKEN）のトークン抽出（後方互換用）
  static String? extractLegacyToken(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final t = uri.queryParameters['t'];
      if (t != null && t.isNotEmpty) return t.trim();
    }
    return null;
  }

  static Future<bool> joinByCode({
    required BuildContext context,
    required String code,
    required String myUid,
  }) async {
    try {
      final db = FirebaseFirestore.instance;

      // まずは code で検索（新フォーマット）
      var cg = await db
          .collectionGroup('invites')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      // 見つからない場合は「旧QR (t=TOKEN)」での参加も試す
      if (cg.docs.isEmpty) {
        // 直前に読み取った RAW をここで受け取れない場合は、
        // 呼び出し側で legacyToken を渡す形にしてもOK。
        // 簡易対応として「code が長い＆記号を含む」なら token かも…等の判定も可。
        // ここでは安全・明示的に、呼び出し側で token を渡す想定にしておきます。
      }

      if (cg.docs.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無効なコードです')),
          );
        }
        return false;
      }

      final inviteRef = cg.docs.first.reference;
      final groupId = inviteRef.parent.parent!.id;

      await db.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([myUid]),
      });
      await db.collection('users').doc(myUid).set({
        'groups': FieldValue.arrayUnion([groupId]),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('参加に失敗しました: $e')));
      }
      return false;
    }
  }
}