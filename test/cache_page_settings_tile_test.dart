import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/cache_page_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('目录缓存开关使用 Riverpod 状态，关闭时清空缓存', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsStore();
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
    final state = CachePageSettingsState(settings, cache);
    final container = ProviderContainer(
      overrides: [cachePageSettingsStateProvider.overrideWithValue(state)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: CachePageSettingsTile(cacheFolders: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchTile = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
    expect(cache.get('-1'), isNotNull);

    await tester.tap(switchTile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(settings.cacheFolders, isFalse);
    expect(cache.get('-1'), isNull);
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);
  });
}
