import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('CachePageSettingsState 读写全部页面与缓存字段', () async {
    final settings = SettingsStore();
    final state = CachePageSettingsState(settings, DriveCache());

    await state.setGridView(false);
    await state.setLaunchPage('drive');
    await state.setCacheFolders(false);
    await state.setLoadAllPages(true);

    expect(state.revision.value, 4);
    expect(state.gridView, isFalse);
    expect(state.launchPage, 'drive');
    expect(state.cacheFolders, isFalse);
    expect(state.loadAllPages, isTrue);
  });

  test('关闭目录缓存时立即清空 DriveCache', () async {
    final cache = DriveCache();
    cache.put(
      '-1',
      CachedFolder(
        folders: const [],
        files: const [],
        path: const [],
        page: 1,
        hasMore: false,
      ),
    );
    final state = CachePageSettingsState(SettingsStore(), cache);
    expect(state.cacheFolders, isTrue);
    expect(cache.get('-1'), isNotNull);

    await state.setCacheFolders(false);

    expect(cache.get('-1'), isNull);
    expect(state.cacheFolders, isFalse);
  });

  test('cachePageSettingsStateProvider 可被共享实例覆盖', () {
    final state = CachePageSettingsState(SettingsStore(), DriveCache());
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
