import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer_connection_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/advanced_connection_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<TransferConnectionSettingsState> _pump(
  WidgetTester tester,
  SettingsStore store,
  AdvancedConnectionSetting setting,
) async {
  final state = TransferConnectionSettingsState(store);
  final container = ProviderContainer(
    overrides: [
      transferConnectionSettingsStateProvider.overrideWithValue(state),
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
          body: AdvancedConnectionSettingsTile(setting: setting),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  setUp(() {
    LanzouClient.apiBase = 'https://pc.woozooo.com';
    LanzouClient.userAgent = '';
    LanzouClient.uploadPath = 'html5up.php';
  });

  tearDown(() {
    LanzouClient.apiBase = 'https://pc.woozooo.com';
    LanzouClient.userAgent = '';
    LanzouClient.uploadPath = 'html5up.php';
  });

  testWidgets('接口域名不依赖 AppController，并同步客户端配置', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = await _pump(
      tester,
      store,
      AdvancedConnectionSetting.apiHost,
    );

    await tester.tap(find.widgetWithText(ListTile, '网盘接口域名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('up.woozooo.com'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.apiHost, 'up');
    expect(LanzouClient.apiBase, 'https://up.woozooo.com');
    expect(state.revision.value, 1);
    expect(find.text('up.woozooo.com'), findsOneWidget);
  });

  testWidgets('上传路径不依赖 AppController，并同步客户端配置', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = await _pump(
      tester,
      store,
      AdvancedConnectionSetting.uploadPath,
    );

    await tester.tap(find.widgetWithText(ListTile, '上传接口路径'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fileup.php'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.uploadPath, 'fileup.php');
    expect(LanzouClient.uploadPath, 'fileup.php');
    expect(state.revision.value, 1);
    expect(find.text('fileup.php'), findsOneWidget);
  });

  testWidgets('User-Agent 支持保存与恢复默认，并同步客户端配置', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = await _pump(
      tester,
      store,
      AdvancedConnectionSetting.userAgent,
    );

    final entry = find.widgetWithText(ListTile, '自定义 User-Agent');
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'LanCloud-test');
    await tester.tap(find.text('保存'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.userAgent, 'LanCloud-test');
    expect(LanzouClient.userAgent, 'LanCloud-test');
    expect(state.revision.value, 1);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.userAgent, isEmpty);
    expect(LanzouClient.userAgent, isEmpty);
    expect(state.revision.value, 2);
    expect(find.text('默认（模拟桌面浏览器）'), findsOneWidget);
  });
}
