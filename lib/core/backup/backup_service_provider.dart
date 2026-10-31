import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup_service.dart';

/// 应用级备份服务；与启动阶段自动备份共用同一实例。
///
/// 服务依赖账号、设置、数据库和恢复后重载的窄边界；应用入口覆盖同一实例，
/// 避免启动自动备份与页面消费各自创建一个服务。
final backupServiceProvider = Provider<BackupService>((ref) {
  throw StateError('backupServiceProvider 必须由应用入口覆盖');
});
