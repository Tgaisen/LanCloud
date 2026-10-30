import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/navigation_appearance_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('导航外观开关不依赖 AppController，并局部刷新', (tester) async {
    for (final setting in NavigationAppearanceSetting.values) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final state = NavigationAppearanceSettingsState(SettingsStore());
      final container = ProviderContainer(
        overrides: [
          navigationAppearanceSettingsStateProvider.overrideWithValue(state),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: NavigationAppearanceSettingsTile(setting: setting),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchTile = find.byType(SwitchListTile);
      final before = tester.widget<SwitchListTile>(switchTile).value;
      await tester.tap(switchTile);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();

      expect(state.revision.value, 1);
      expect(tester.widget<SwitchListTile>(switchTile).value, isNot(before));

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('底栏显示项取消不写入，确认后一次提交', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = NavigationAppearanceSettingsState(store);
    final container = ProviderContainer(
      overrides: [
        navigationAppearanceSettingsStateProvider.overrideWithValue(state),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: NavBarItemsSettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, '底栏显示项'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('传输'),
      ),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(store.navShowTransfers, isFalse);
    expect(store.navShowFavorites, isFalse);
    expect(state.revision.value, 0);

    await tester.tap(find.widgetWithText(ListTile, '底栏显示项'));
    await tester.pumpAndSettle();
    for (final label in ['传输', '收藏']) {
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(label),
        ),
      );
    }
    await tester.tap(find.text('确定'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.navShowTransfers, isTrue);
    expect(store.navShowFavorites, isTrue);
    expect(state.revision.value, 1);
    expect(find.text('首页 · 网盘 · 传输 · 收藏 · 我的'), findsOneWidget);
  });
}
