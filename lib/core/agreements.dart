import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';

/// 用户协议 / 隐私政策的同意状态（按版本号记录）。
class Agreements {
  static const _key = 'terms_accepted_version';

  /// 读取失败时不阻塞使用（例如存储异常）。
  static Future<bool> accepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getInt(_key) ?? 0) >= termsVersion;
    } catch (_) {
      return true;
    }
  }

  static Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, termsVersion);
  }
}
