import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/lanzou_client.dart';
import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 将接口主机设置映射为蓝奏云 API 根地址。
String lanzouApiBaseForHost(String host) =>
    host == 'up' ? 'https://up.woozooo.com' : 'https://pc.woozooo.com';

/// 传输并发与蓝奏云连接参数的明确读写入口。
class TransferConnectionSettingsState {
  TransferConnectionSettingsState(this.store);

  final SettingsStore store;
  final ValueNotifier<int> revision = ValueNotifier(0);

  int get requestInterval => store.requestInterval;
  int get maxUploads => store.maxUploads;
  int get maxDownloads => store.maxDownloads;
  String get apiHost => store.apiHost;
  String get userAgent => store.userAgent;
  String get uploadPath => store.uploadPath;

  Future<void> setRequestInterval(int value) async {
    await store.setRequestInterval(value);
    LanzouClient.requestInterval = Duration(milliseconds: value);
    revision.value += 1;
  }

  Future<void> setMaxUploads(int value) async {
    await store.setMaxUploads(value);
    revision.value += 1;
  }

  Future<void> setMaxDownloads(int value) async {
    await store.setMaxDownloads(value);
    revision.value += 1;
  }

  Future<void> setApiHost(String value) async {
    await store.setApiHost(value);
    LanzouClient.apiBase = lanzouApiBaseForHost(value);
    revision.value += 1;
  }

  Future<void> setUserAgent(String value) async {
    await store.setUserAgent(value);
    LanzouClient.userAgent = value;
    revision.value += 1;
  }

  Future<void> setUploadPath(String value) async {
    await store.setUploadPath(value);
    LanzouClient.uploadPath = value;
    revision.value += 1;
  }
}

final transferConnectionSettingsStateProvider =
    Provider<TransferConnectionSettingsState>(
      (ref) => TransferConnectionSettingsState(
        ref.watch(settingsStoreProvider),
      ),
    );
