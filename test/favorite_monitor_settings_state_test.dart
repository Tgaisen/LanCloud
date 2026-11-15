import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/favorite_monitor_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('收藏检测设置默认关闭、每周、全部文件夹、更新通知开启', () async {
    final store = SettingsStore();
    await store.load();
    final state = FavoriteMonitorSettingsState(store);

    expect(state.autoCheck, isFalse);
    expect(state.frequency, FavoriteCheckFrequency.weekly);
    expect(state.checkAll, isTrue);
    expect(state.checkRefs, isEmpty);
    expect(state.notifyUpdates, isTrue);
  });

  test('收藏检测设置可持久化并规范化指定范围', () async {
    final store = SettingsStore();
    await store.load();
    final state = FavoriteMonitorSettingsState(store);

    await state.setAutoCheck(true);
    await state.setFrequency(FavoriteCheckFrequency.monthly);
    await state.setScope(
      all: false,
      refs: {'https://share.example/b', '', 'https://share.example/a'},
    );
    await state.setNotifyUpdates(false);

    expect(state.revision.value, 4);
    expect(
      store.favoriteCheckRefsJson,
      '["https://share.example/a","https://share.example/b"]',
    );

    final reloaded = SettingsStore();
    await reloaded.load();
    final restored = FavoriteMonitorSettingsState(reloaded);
    expect(restored.autoCheck, isTrue);
    expect(restored.frequency, FavoriteCheckFrequency.monthly);
    expect(restored.checkAll, isFalse);
    expect(restored.checkRefs, {
      'https://share.example/a',
      'https://share.example/b',
    });
    expect(restored.notifyUpdates, isFalse);

    final backup = reloaded.toJson();
    expect(backup['favorite_monitor_auto_check'], isTrue);
    expect(backup['favorite_monitor_frequency'], 'monthly');
    expect(backup['favorite_monitor_check_all'], isFalse);
    expect(backup['favorite_monitor_update_notify'], isFalse);
  });

  test('损坏的指定范围 JSON 按空集处理', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'favorite_monitor_check_refs': '{bad json',
    });
    final store = SettingsStore();
    await store.load();

    expect(FavoriteMonitorSettingsState(store).checkRefs, isEmpty);
  });

  test('favoriteMonitorSettingsStateProvider 可被应用共享实例覆盖', () {
    final state = FavoriteMonitorSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [
        favoriteMonitorSettingsStateProvider.overrideWithValue(state),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(favoriteMonitorSettingsStateProvider), state),
      isTrue,
    );
  });
}
