import '../data/settings_store.dart';
import '../download_target.dart';
import 'transfer_account_port.dart';
import 'transfer_store.dart';

/// `TransferManager` 在迁移期需要的最小应用能力边界。
///
/// 由旧 `AppController` 实现，避免传输管理器直接依赖完整控制器；后续可将
/// 这些能力逐项替换为独立 provider。
abstract interface class TransferAppAdapter {
  TransferStore get transferStore;
  TransferAccountPort get transferAccounts;
  SettingsStore get settings;

  Future<DownloadTargetMode> downloadTargetMode();
  String? get safDownloadTree;
  Future<String> safTempFilePath(String taskId, String name);
  Future<String> uniqueSavePath(String name);
}
