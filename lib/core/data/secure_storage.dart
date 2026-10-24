import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全应用共用的安全存储配置。
///
/// - Windows v10 默认不再读取 v9 的 Credential Manager 数据，必须开启
///   `useBackwardCompatibility`；首次读取时旧值会写入新的加密文件并清理旧项。
/// - Android 从 v9 首次启动 v10 时会迁移加密算法，开启备份可在迁移中断时
///   避免不可恢复的数据丢失。
const lanCloudSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(migrateWithBackup: true),
  wOptions: WindowsOptions(useBackwardCompatibility: true),
);

/// v11 首次升级检查只执行一次。
///
/// v9 的旧密文可能作为不可读残留继续存在；v11 的查询会一直报告
/// `legacyDataUnreadable`，即使新版本写入的账号数据已经正常工作。记录检查
/// 完成后不再重复提示，避免每次启动都误报“需要重新登录”。
const secureStorageUpgradeCheckKey = 'secure_storage_v11_upgrade_checked';

Future<SecureStorageUpgradeStatus?> checkSecureStorageUpgradeOnce({
  Future<SecureStorageUpgradeStatus> Function()? check,
  Future<SharedPreferences> Function()? preferencesLoader,
}) async {
  final prefs = await (preferencesLoader ?? SharedPreferences.getInstance)();
  if (prefs.getBool(secureStorageUpgradeCheckKey) ?? false) return null;

  final status =
      await (check ?? () => lanCloudSecureStorage.checkUpgradeStatus())();
  await prefs.setBool(secureStorageUpgradeCheckKey, true);
  return status;
}
