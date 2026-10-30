import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings_store.dart';
import 'data/settings_store_provider.dart';

/// 进度通知与完成通知开关的单一读写入口。
///
/// 持久化仍由 [SettingsStore] 负责，本状态不复制字段。
class NotificationSettingsState {
  const NotificationSettingsState(this.store);

  final SettingsStore store;

  bool get notifyProgress => store.notifyProgress;

  bool get notifyDone => store.notifyDone;

  Future<void> setNotifyProgress(bool value) =>
      store.setNotifyProgress(value);

  Future<void> setNotifyDone(bool value) => store.setNotifyDone(value);
}

final notificationSettingsStateProvider =
    Provider<NotificationSettingsState>(
      (ref) => NotificationSettingsState(ref.watch(settingsStoreProvider)),
    );
