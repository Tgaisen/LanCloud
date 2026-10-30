import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 传输并发与蓝奏云连接参数的明确读写入口。
class TransferConnectionSettingsState {
  const TransferConnectionSettingsState(this.store);

  final SettingsStore store;

  int get requestInterval => store.requestInterval;
  int get maxUploads => store.maxUploads;
  int get maxDownloads => store.maxDownloads;
  String get apiHost => store.apiHost;
  String get userAgent => store.userAgent;
  String get uploadPath => store.uploadPath;

  Future<void> setRequestInterval(int value) =>
      store.setRequestInterval(value);
  Future<void> setMaxUploads(int value) => store.setMaxUploads(value);
  Future<void> setMaxDownloads(int value) => store.setMaxDownloads(value);
  Future<void> setApiHost(String value) => store.setApiHost(value);
  Future<void> setUserAgent(String value) => store.setUserAgent(value);
  Future<void> setUploadPath(String value) => store.setUploadPath(value);
}

final transferConnectionSettingsStateProvider =
    Provider<TransferConnectionSettingsState>(
      (ref) => TransferConnectionSettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
