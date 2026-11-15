import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/favorite_monitor_models.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/favorites_page.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

Widget _host(
  AppEnvironment environment,
  Widget home, {
  TransferManager? transfers,
}) => ProviderScope(
  overrides: [
    accountStateProvider.overrideWithValue(environment.accountState),
    lanzouClientRegistryProvider.overrideWithValue(environment.clientRegistry),
    appDbProvider.overrideWithValue(environment.db),
    driveStateProvider.overrideWithValue(environment.drive),
    listHomeSettingsStateProvider.overrideWithValue(
      environment.listHomeSettings,
    ),
    navigationAppearanceSettingsStateProvider.overrideWithValue(
      environment.navigationAppearanceSettings,
    ),
    navigationStateProvider.overrideWithValue(environment.navigation),
    if (transfers != null) transferManagerProvider.overrideWithValue(transfers),
  ],
  child: MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: home,
  ),
);

void main() {
  testWidgets('收藏视图可独立打开，空收藏时显示提示', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await tester.pumpWidget(_host(environment, const FavoritesPage()));
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('暂无收藏内容'), findsOneWidget);
  });

  testWidgets('独立页面：多选时返回只退出多选，不退出页面', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await tester.pumpWidget(
      _host(
        environment,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    // 独立打开时外壳传的就是同一个 tabIndex（见 app.dart
                    // 的 _openView），这里保持一致，避免判断错页面形态
                    builder: (_) => const FavoritesPage(tabIndex: 3),
                  ),
                ),
                child: const Text('打开收藏'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();

    // 排序是独立 AppBar 按钮，在搜索右侧。
    expect(find.byTooltip('排序'), findsOneWidget);
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    List<String> menuLabels() => tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .map((row) => row.label)
        .toList();
    expect(menuLabels(), ['时间', '名称', '大小', '升序']);
    final ascendingCheck = find.byKey(
      const ValueKey('m3e-menu-selected-check-升序'),
    );
    expect(ascendingCheck, findsNothing);
    await tester.tap(find.text('升序'));
    await tester.pumpAndSettle();
    expect(ascendingCheck, findsOneWidget);
    await tester.tap(find.text('名称'));
    await tester.pumpAndSettle();
    expect(find.text('时间'), findsNothing);
    expect(ascendingCheck, findsNothing);
    expect(environment.listHomeSettings.favoritesSortMode, 'name');
    expect(environment.listHomeSettings.favoritesSortAscending, isTrue);

    // 空收藏也能进多选；批量检测项仍保留但会提示没有可检测项目。
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(menuLabels(), hasLength(4));
    expect(menuLabels().first, '多选');
    expect(menuLabels(), contains('检测收藏文件夹更新'));
    expect(menuLabels(), contains('检测失效项目'));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.widgetWithText(M3eMenuRow, '检测收藏文件夹更新'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.folder_check,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.widgetWithText(M3eMenuRow, '检测失效项目'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.document_search,
    );
    expect(find.text('时间'), findsNothing);
    expect(find.text('名称'), findsNothing);
    expect(find.text('大小'), findsNothing);
    // 图标与传输页顶栏的多选入口一致（Checklist）
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.widgetWithText(M3eMenuRow, '多选'),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.checklist,
    );
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(environment.navigation.selectionMode, isTrue);

    // 第一次返回：退出多选，页面还在
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(environment.navigation.selectionMode, isFalse);
    expect(find.byType(FavoritesPage), findsOneWidget);

    // 再返回一次才退出页面
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsNothing);
  });

  // 搜索框打开时返回键先退出搜索（与分享浏览页一致），再退出页面
  testWidgets('独立页面：搜索时返回只退出搜索，不退出页面', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await tester.pumpWidget(
      _host(
        environment,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FavoritesPage(tabIndex: 3),
                  ),
                ),
                child: const Text('打开收藏'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();

    // 打开搜索：搜索框是带过渡淡入的
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpAndSettle();

    // 第一次返回：只退出搜索，页面还在
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FavoritesPage), findsOneWidget);

    // 再返回一次才退出页面
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsNothing);
  });

  testWidgets('收藏多选：分区可选择全部或仅选择已失效项', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final transfers = buildTransferManagerForEnvironment(environment);
    addTearDown(transfers.dispose);
    await tester.runAsync(() async {
      await environment.db.addFavorite(
        kind: 'shareFolder',
        name: '普通文件夹',
        ref: 'https://example.com/folder-ok',
      );
      await environment.db.addFavorite(
        kind: 'shareFolder',
        name: '失效文件夹',
        ref: 'https://example.com/folder-invalid',
      );
      await environment.db.addFavorite(
        kind: 'shareFile',
        name: '普通文件.txt',
        ref: 'https://example.com/file-ok',
      );
      await environment.db.addFavorite(
        kind: 'shareFile',
        name: '失效文件.txt',
        ref: 'https://example.com/file-invalid',
      );
      final favorites = await environment.db.favorites();
      for (final favorite in favorites.where(
        (item) => item.ref.contains('invalid'),
      )) {
        await environment.db.saveFavoriteShareStatus(
          id: favorite.id,
          status: FavoriteShareStatus.unavailable,
          checkedAt: 1,
        );
      }
    });

    await tester.pumpWidget(
      _host(environment, const FavoritesPage(), transfers: transfers),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('favorites-folders-select-all')),
      findsNothing,
    );
    expect(find.text('选择'), findsNothing);
    expect(find.text('选择失效'), findsNothing);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('favorites-folders-select-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('favorites-files-select-unavailable')),
      findsOneWidget,
    );
    expect(find.text('选择'), findsNWidgets(2));
    expect(find.text('选择失效'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('favorites-files-select-all')));
    await tester.pump();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('favorites-folders-select-unavailable')),
    );
    await tester.pump();
    expect(find.text('已选择 3 项'), findsOneWidget);
  });
}
