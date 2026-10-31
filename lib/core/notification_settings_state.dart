import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 进度通知与完成通知开关的单一读写入口。
///
/// 持久化仍由 [SettingsStore] 负责，本状态不复制字段。
class NotificationSettingsState {
  NotificationSettingsState(this.store);

  final SettingsStore store;
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool get notifyProgress => store.notifyProgress;

  bool get notifyDone => store.notifyDone;

  Future<void> setNotifyProgress(bool value) async {
    await store.setNotifyProgress(value);
    revision.value += 1;
  }

  Future<void> setNotifyDone(bool value) async {
    await store.setNotifyDone(value);
    revision.value += 1;
  }
}

final notificationSettingsStateProvider = Provider<NotificationSettingsState>(
  (ref) => NotificationSettingsState(ref.watch(settingsStoreProvider)),
);
