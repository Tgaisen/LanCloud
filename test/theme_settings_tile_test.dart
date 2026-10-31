import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/core/theme_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/theme_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(SettingsStore, ThemeSettingsState)> _pump(
  WidgetTester tester,
  Widget Function(ThemeSettingsState state) build,
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
        home: Scaffold(body: build(state)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (store, state);
}

void main() {
  setUp(() => SystemMotion.motionMode.value = 'auto');

  tearDown(() => SystemMotion.motionMode.value = 'auto');

  testWidgets('主题模式使用 Riverpod 状态，并局部刷新', (tester) async {
    final (store, state) = await _pump(
      tester,
      (_) => const ThemeSettingsTile(type: ThemeSettingsTileType.mode),
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

  testWidgets('纯黑深色开关使用 Riverpod 状态，并局部刷新', (tester) async {
    final (store, state) = await _pump(
      tester,
      (_) => const ThemeSettingsTile(type: ThemeSettingsTileType.oledBlack),
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

  testWidgets('全局动画使用 Riverpod 状态，并同步 SystemMotion', (tester) async {
    final (store, state) = await _pump(
      tester,
      (_) => const MotionSettingsTile(),
    );

    expect(find.text('自动'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '全局动画'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('禁用'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.motionMode, 'off');
    expect(SystemMotion.motionMode.value, 'off');
    expect(state.revision.value, 1);
    expect(find.text('禁用'), findsOneWidget);
  });

  testWidgets('主题色弹窗使用 Riverpod 状态，并保持动态色与 seed 互斥', (tester) async {
    final (store, state) = await _pump(
      tester,
      (_) => const ThemeColorSettingsTile(dynamicSupported: true),
    );

    final entry = find.widgetWithText(ListTile, '主题色');
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('动态取色'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.dynamicColor, isTrue);
    expect(state.revision.value, 1);
    expect(find.text('动态取色'), findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认蓝'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.dynamicColor, isFalse);
    expect(store.themeSeed, 0xFF2E6BE6);
    expect(state.revision.value, 3);
    expect(find.text('默认蓝'), findsOneWidget);
  });
}
