import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/theme_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/theme_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(SettingsStore, ThemeSettingsState)> _pumpTile(
  WidgetTester tester,
  ThemeSettingsTileType type,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = SettingsStore();
  final state = ThemeSettingsState(store);
  final container = ProviderContainer(
    overrides: [themeSettingsStateProvider.overrideWithValue(state)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: ThemeSettingsTile(type: type)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (store, state);
}

void main() {
  testWidgets('主题模式不依赖 AppController，并局部刷新', (tester) async {
    final (store, state) = await _pumpTile(
      tester,
      ThemeSettingsTileType.mode,
    );

    final group = find.byType(M3eConnectedButtonGroup<String>);
    expect(
      tester.widget<M3eConnectedButtonGroup<String>>(group).selected,
      'system',
    );

    await tester.tap(find.text('深色').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.themeMode, 'dark');
    expect(state.revision.value, 1);
    expect(
      tester.widget<M3eConnectedButtonGroup<String>>(group).selected,
      'dark',
    );
  });

  testWidgets('纯黑深色开关不依赖 AppController，并局部刷新', (tester) async {
    final (store, state) = await _pumpTile(
      tester,
      ThemeSettingsTileType.oledBlack,
    );

    final switchTile = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);

    await tester.tap(switchTile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.oledBlack, isTrue);
    expect(state.revision.value, 1);
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
  });
}
