import '../api/lanzou_client.dart';
import '../data/account_store.dart';
import '../data/app_db.dart';
import '../data/settings_store.dart';
import '../download_target.dart';

/// `TransferManager` 在迁移期需要的最小应用能力边界。
///
/// 由旧 `AppController` 实现，避免传输管理器直接依赖完整控制器；后续可将
/// 这些能力逐项替换为独立 provider。
abstract interface class TransferAppAdapter {
  AppDb get db;
  String? get activeUid;
  AccountStore get accounts;
  SettingsStore get settings;
  LanzouClient get publicClient;

  LanzouClient clientFor(String uid);
  Future<DownloadTargetMode> downloadTargetMode();
  String? get safDownloadTree;
  Future<String> safTempFilePath(String taskId, String name);
  Future<String> uniqueSavePath(String name);
}
