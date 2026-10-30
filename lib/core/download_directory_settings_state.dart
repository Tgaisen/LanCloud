import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';
import 'saf_storage.dart';

/// 下载目录持久化字段的明确读写入口。
class DownloadDirectorySettingsState {
  DownloadDirectorySettingsState(
    this.store, {
    Future<void> Function(String uri)? releaseSaf,
  }) : releaseSaf = releaseSaf ?? SafStorage.release;

  final SettingsStore store;
  final Future<void> Function(String uri) releaseSaf;
  final ValueNotifier<int> revision = ValueNotifier(0);

  String? get directoryPath => store.downloadDir;
  String? get safariTreeUri => store.downloadDirTree;
  String? get safariLabel => store.downloadDirLabel;

  Future<void> selectDirectoryPath(String? value) async {
    final oldTree = store.downloadDirTree;
    await store.setDownloadDir(value);
    await store.setDownloadDirTree(null, null);
    if (oldTree != null && oldTree.isNotEmpty) await releaseSaf(oldTree);
    revision.value += 1;
  }

  Future<void> selectSafariDirectory(SafDirectory dir) async {
    final oldTree = store.downloadDirTree;
    await store.setDownloadDirTree(dir.uri, dir.label);
    await store.setDownloadDir(null);
    if (oldTree != null && oldTree.isNotEmpty && oldTree != dir.uri) {
      await releaseSaf(oldTree);
    }
    revision.value += 1;
  }
}

final downloadDirectorySettingsStateProvider =
    Provider<DownloadDirectorySettingsState>(
      (ref) => DownloadDirectorySettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
