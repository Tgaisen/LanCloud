import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/page_behavior_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  ProviderContainer container,
) async {
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认启动页不依赖 AppController，并局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = CachePageSettingsState(store, DriveCache());
    final container = ProviderContainer(
      overrides: [cachePageSettingsStateProvider.overrideWithValue(state)],
    );
    await _pump(
      tester,
      const LaunchPageSettingsTile(),
      container,
    );

    expect(find.text('首页'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '默认启动页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网盘'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.launchPage, 'drive');
    expect(state.revision.value, 1);
    expect(find.text('网盘'), findsOneWidget);
  });

  testWidgets('首页目录打开方式不依赖 AppController，并局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = ListHomeSettingsState(store);
    final container = ProviderContainer(
      overrides: [listHomeSettingsStateProvider.overrideWithValue(state)],
    );
    await _pump(
      tester,
      const HomeFolderOpenSettingsTile(),
      container,
    );

    expect(find.text('网盘页'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '首页目录打开方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新页面'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.homeFolderOpenMode, 'page');
    expect(state.revision.value, 1);
    expect(find.text('新页面'), findsOneWidget);
  });
}
