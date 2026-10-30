import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 下载目录持久化字段的明确读写入口。
class DownloadDirectorySettingsState {
  const DownloadDirectorySettingsState(this.store);

  final SettingsStore store;

  String? get directoryPath => store.downloadDir;
  String? get safariTreeUri => store.downloadDirTree;
  String? get safariLabel => store.downloadDirLabel;

  Future<void> setDirectoryPath(String? value) =>
      store.setDownloadDir(value);
  Future<void> setSafariDirectory(String? treeUri, String? label) =>
      store.setDownloadDirTree(treeUri, label);
}

final downloadDirectorySettingsStateProvider =
    Provider<DownloadDirectorySettingsState>(
      (ref) => DownloadDirectorySettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
