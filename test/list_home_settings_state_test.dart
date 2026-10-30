import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/core/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('ListHomeSettingsState 读写全部列表与首页字段', () async {
    final settings = SettingsStore();
    final state = ListHomeSettingsState(settings);

    await state.setSortMode('name');
    await state.setQuickExpanded(false);
    await state.setRecentsExpanded(false);
    await state.setRecentLimit(20);
    await state.setHomeFolderOpenMode('page');

    expect(state.sortMode, 'name');
    expect(state.quickExpanded, isFalse);
    expect(state.recentsExpanded, isFalse);
    expect(state.recentLimit, 20);
    expect(state.homeFolderOpenMode, 'page');
  });

  test('AppController 旧 API 保持设置写入与通知行为', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);
    var notifications = 0;
    app.addListener(() => notifications += 1);

    await app.setSortMode('name');
    await app.setQuickExpanded(false);
    await app.setRecentsExpanded(false);
    await app.setRecentLimit(20);
    await app.setHomeFolderOpenMode('page');

    expect(app.settings.sortMode, 'name');
    expect(app.settings.quickExpanded, isFalse);
    expect(app.settings.recentsExpanded, isFalse);
    expect(app.settings.recentLimit, 20);
    expect(app.settings.homeFolderOpenMode, 'page');
    expect(notifications, 5);
  });

  test('listHomeSettingsStateProvider 可被共享实例覆盖', () {
    final state = ListHomeSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [listHomeSettingsStateProvider.overrideWithValue(state)],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(listHomeSettingsStateProvider), state),
      isTrue,
    );
  });
}
