import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 积分任务签名（与原项目一致的 MD5 拼接算法）。
class SignUtils {
  static const String _salt = 'aslkdvcniu34h9tgufh278wv2';

  /// 生成积分领取签名。
  static String generateScoreSign({
    required String adId,
    required String token,
    required String uid,
    required int localTs,
    required int serverTs,
  }) {
    // 与原项目保持一致：md5(adId + token + uid + localTs + serverTs + salt)
    final raw = '$adId$token$uid$localTs$serverTs$_salt';
    return md5.convert(utf8.encode(raw)).toString();
  }
}
