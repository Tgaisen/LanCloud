import 'transfer_account_port.dart';
import 'transfer_download_port.dart';
import 'transfer_settings_port.dart';
import 'transfer_store.dart';

/// `TransferManager` 的显式应用级依赖集合。
class TransferDependencies {
  const TransferDependencies({
    required this.store,
    required this.accounts,
    required this.download,
    required this.settings,
  });

  final TransferStore store;
  final TransferAccountPort accounts;
  final TransferDownloadPort download;
  final TransferSettingsPort settings;
}

/// 应用入口向 `TransferManager` 提供依赖集合。
abstract interface class TransferDependenciesProvider {
  TransferDependencies get transferDependencies;
}
