import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup_service.dart';

/// 应用级备份服务；与启动阶段自动备份共用同一实例。
///
/// 服务内部迁移前仍依赖 AppController 完成账号、设置、数据库和恢复后重载，
/// 因此由应用入口覆盖，不在 provider 内重复组装。
final backupServiceProvider = Provider<BackupService>((ref) {
  throw StateError('backupServiceProvider 必须由应用入口覆盖');
});
