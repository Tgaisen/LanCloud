import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/favorite_monitor_settings_state.dart';
import 'package:lancloud/core/favorites/favorite_check_gateway.dart';
import 'package:lancloud/core/favorites/favorite_monitor_reporter.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/favorite_monitor_settings_tile.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeGateway implements FavoriteCheckGateway {
  @override
  Future<FolderShareDetail> resolveFolder({
    required String url,
    required String pwd,
  }) async => FolderShareDetail(name: '文件夹');

  @override
  Future<bool> validateFile({required String url, required String pwd}) async =>
      true;
}

Widget _host(AppEnvironment environment, Widget child) => ProviderScope(
  overrides: [
    appDbProvider.overrideWithValue(environment.db),
    favoriteMonitorSettingsStateProvider.overrideWithValue(
      environment.favoriteMonitorSettings,
    ),
    favoriteCheckGatewayProvider.overrideWithValue(_FakeGateway()),
    favoriteMonitorReporterProvider.overrideWithValue(
      const NoopFavoriteMonitorReporter(),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDownAll(() async {
    try {
      await (await AppDb.instance.db).close();
    } catch (_) {}
  });

  testWidgets('自动检测开关默认关闭；无通知权限时仍可开启并提示', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    bool? permission;

    await tester.pumpWidget(
      _host(
        environment,
        Center(
          child: FavoriteAutoCheckSettingsTile(
            requestPermission: () async => false,
            runCheckOnEnable: false,
            onPermissionChanged: (value) => permission = value,
          ),
        ),
      ),
    );

    expect(environment.favoriteMonitorSettings.autoCheck, isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(permission, isFalse);
    expect(environment.favoriteMonitorSettings.autoCheck, isTrue);
    expect(find.text('通知权限未开启，请到系统设置中允许通知'), findsOneWidget);
  });

  testWidgets('自动检测关闭时，范围和频率行禁用', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      _host(
        environment,
        const Column(
          children: [
            FavoriteCheckScopeSettingsTile(),
            FavoriteCheckFrequencySettingsTile(),
          ],
        ),
      ),
    );

    final scope = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '检测范围'),
    );
    final frequency = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '检测频率'),
    );
    expect(scope.enabled, isFalse);
    expect(frequency.enabled, isFalse);
  });

  testWidgets('收藏更新通知默认开启，无系统权限时仍保存开关值', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await tester.pumpWidget(
      _host(
        environment,
        Center(
          child: FavoriteUpdateNotificationSettingsTile(
            requestPermission: () async => false,
          ),
        ),
      ),
    );

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(environment.favoriteMonitorSettings.notifyUpdates, isFalse);
  });

  testWidgets('检测范围弹层默认全选，可取消单个文件夹后保存', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    FavoriteCheckScopeSelection? result;
    var folders = <FavoriteItem>[];

    await tester.pumpWidget(
      _host(
        environment,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showFavoriteCheckScopeDialog(
                  context,
                  folders: folders,
                  initial: const FavoriteCheckScopeSelection(
                    all: true,
                    refs: <String>{},
                  ),
                );
              },
              child: const Text('选择'),
            ),
          ),
        ),
      ),
    );

    folders =
        await tester.runAsync(() async {
          await environment.db.importTables({'favorites': <Object?>[]});
          await environment.db.addFavorite(
            kind: 'shareFolder',
            name: '文件夹 A',
            ref: 'https://share.example/a',
          );
          await environment.db.addFavorite(
            kind: 'shareFolder',
            name: '文件夹 B',
            ref: 'https://share.example/b',
          );
          return environment.db.favorites();
        }) ??
        <FavoriteItem>[];

    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(find.text('全部收藏文件夹'), findsOneWidget);
    expect(find.text('文件夹 A'), findsOneWidget);
    expect(find.text('文件夹 B'), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, '文件夹 B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.all, isFalse);
    expect(result!.refs, {'https://share.example/a'});
  });
}
