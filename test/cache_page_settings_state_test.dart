import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:lancloud/core/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('CachePageSettingsState 读写全部页面与缓存字段', () async {
    final settings = SettingsStore();
    final state = CachePageSettingsState(settings);

    await state.setGridView(false);
    await state.setLaunchPage('drive');
    await state.setCacheFolders(false);
    await state.setLoadAllPages(true);

    expect(state.gridView, isFalse);
    expect(state.launchPage, 'drive');
    expect(state.cacheFolders, isFalse);
    expect(state.loadAllPages, isTrue);
  });

  test('关闭目录缓存时旧 API 仍立即清空 DriveCache', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);
    app.driveCache.put(
      '-1',
      CachedFolder(
        folders: const [],
        files: const [],
        path: const [],
        page: 1,
        hasMore: false,
      ),
    );
    expect(app.driveCache.get('-1'), isNotNull);

    await app.setCacheFolders(false);

    expect(app.driveCache.get('-1'), isNull);
    expect(app.settings.cacheFolders, isFalse);
  });

  test('cachePageSettingsStateProvider 可被共享实例覆盖', () {
    final state = CachePageSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [cachePageSettingsStateProvider.overrideWithValue(state)],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(cachePageSettingsStateProvider), state),
      isTrue,
    );
  });
}
