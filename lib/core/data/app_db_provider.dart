import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_db.dart';

/// 应用数据库的 Riverpod 入口。
///
/// 当前仍返回既有单例，保证 Provider / Riverpod 双栈期间只有同一份数据库
/// 连接；应用级依赖常驻，不使用 `autoDispose`。
final appDbProvider = Provider<AppDb>((ref) => AppDb.instance);
