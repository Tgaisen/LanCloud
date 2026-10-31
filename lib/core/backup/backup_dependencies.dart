import '../data/account_store.dart';
import '../data/app_db.dart';
import '../data/settings_store.dart';

/// 备份服务需要读写的数据与恢复后重载能力。
///
/// 旧的 `AppController` 在退役期实现该接口；备份服务本身只依赖这个窄边界，
/// 不再导入或持有整个应用控制器。
abstract interface class BackupDependencies {
  AccountStore get accounts;
  SettingsStore get settings;
  AppDb get db;

  Future<void> reloadFromStorage();
}

/// 用现有存储和一次重载回调组装备份依赖，不依赖完整应用控制器。
final class BackupStoreDependencies implements BackupDependencies {
  BackupStoreDependencies({
    required this.accounts,
    required this.settings,
    required this.db,
    required this.reloadCallback,
  });

  @override
  final AccountStore accounts;

  @override
  final SettingsStore settings;

  @override
  final AppDb db;

  final Future<void> Function() reloadCallback;

  @override
  Future<void> reloadFromStorage() => reloadCallback();
}
