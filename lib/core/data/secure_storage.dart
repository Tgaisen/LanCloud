import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
