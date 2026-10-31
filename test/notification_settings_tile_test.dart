import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/notification_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('完成通知设置行使用新文案和 Riverpod 状态', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsStore();
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);
    bool? permission;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: NotificationSettingsTile(
              done: true,
              requestPermission: () async => true,
              onPermissionChanged: (value) => permission = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('传输完成通知'), findsOneWidget);
    expect(find.text('下载或上传完成、失败时通知'), findsOneWidget);
    final switchTile = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);

    await tester.tap(switchTile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
    expect(settings.notifyDone, isFalse);

    await tester.tap(switchTile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(settings.notifyDone, isTrue);
    expect(permission, isTrue);
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
  });
}
