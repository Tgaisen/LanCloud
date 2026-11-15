import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/drive_page.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

class _CleanupClient extends LanzouClient {
  _CleanupClient({required this.files, required this.hasMore})
    : super(uid: '1');

  final List<LzFile> files;
  final bool hasMore;
  final List<String> deletedIds = [];
  final Set<String> failingIds = <String>{};

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async => (folders: const <LzFolder>[], path: const <PathNode>[]);

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async => page == 1
      ? (files: files, hasMore: hasMore)
      : (files: const <LzFile>[], hasMore: false);

  @override
  Future<void> deleteItem({required String id, required bool isFile}) async {
    if (failingIds.contains(id)) {
      throw const LanzouException('delete failed');
    }
    deletedIds.add(id);
  }
}

class _FakeApp {
  _FakeApp() {
    environment.accountState.store.activeUid = '1';
  }

  final AppEnvironment environment = AppEnvironment();

  void dispose() => environment.dispose();
}

List<Override> _overrides(
  _FakeApp app,
  TransferManager manager,
  LanzouClient client,
) => [
  transferManagerProvider.overrideWithValue(manager),
  lanzouClientRegistryProvider.overrideWithValue(
    LanzouClientRegistry(factory: (_) => client),
  ),
  accountStateProvider.overrideWithValue(app.environment.accountState),
  appDbProvider.overrideWithValue(app.environment.db),
  driveStateProvider.overrideWithValue(app.environment.drive),
  cachePageSettingsStateProvider.overrideWithValue(
    app.environment.cachePageSettings,
  ),
  listHomeSettingsStateProvider.overrideWithValue(
    app.environment.listHomeSettings,
  ),
  navigationAppearanceSettingsStateProvider.overrideWithValue(
    app.environment.navigationAppearanceSettings,
  ),
  navigationStateProvider.overrideWithValue(app.environment.navigation),
];

Future<_FakeApp> _pumpDrive(WidgetTester tester, LanzouClient client) async {
  final app = _FakeApp();
  addTearDown(app.dispose);
  final manager = buildTransferManagerForEnvironment(app.environment);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(app, manager, client),
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const DrivePage(tabIndex: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

Future<void> _openCleanup(WidgetTester tester) async {
  await tester.tap(find.byTooltip('菜单'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('清理同名文件'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('同名文件弹窗按服务端顺序保留最新并批量删除其余文件', (tester) async {
    final client = _CleanupClient(
      hasMore: true,
      files: [
        LzFile(id: 'newest', name: 'same.zip', time: '3 天前', size: '3 M'),
        LzFile(id: 'older', name: 'same.zip', time: '4 天前', size: '2 M'),
        LzFile(id: 'oldest', name: 'same.zip', time: '5 天前', size: '1 M'),
        for (var i = 0; i < 20; i++)
          LzFile(
            id: 'filler-$i',
            name: 'filler-$i.zip',
            time: '6 天前',
            size: '1 M',
          ),
      ],
    );
    await _pumpDrive(tester, client);
    await _openCleanup(tester);

    expect(find.text('该目录下的同名文件'), findsOneWidget);
    expect(find.text('未加载全部内容，结果可能不全'), findsOneWidget);
    expect(find.text('3 项'), findsOneWidget);
    expect(find.text('共 1 组 3 个同名文件'), findsOneWidget);

    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    expect(deleteButton.onPressed, isNull);

    await tester.tap(find.text('保留最新'));
    await tester.pump();
    final checked = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .where((checkbox) => checkbox.value == true)
        .length;
    expect(checked, 2);

    await tester.tap(find.byKey(const ValueKey('same-name-file-newest')).last);
    await tester.pump();
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .where((checkbox) => checkbox.value == true)
          .length,
      2,
      reason: '每组必须至少保留一个文件',
    );

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('将把选中的 2 个同名文件移入回收站，继续吗？'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await tester.pumpAndSettle();

    expect(client.deletedIds, containsAll(<String>['older', 'oldest']));
    expect(client.deletedIds, isNot(contains('newest')));
    expect(find.text('已删除 2 个同名文件'), findsOneWidget);
  });

  testWidgets('同名文件单项删除失败时保留失败项并提示部分成功', (tester) async {
    final client = _CleanupClient(
      hasMore: false,
      files: [
        LzFile(id: 'newest', name: 'same.zip', time: '3 天前', size: '3 M'),
        LzFile(id: 'older', name: 'same.zip', time: '4 天前', size: '2 M'),
        LzFile(id: 'oldest', name: 'same.zip', time: '5 天前', size: '1 M'),
      ],
    )..failingIds.add('older');
    await _pumpDrive(tester, client);
    await _openCleanup(tester);

    await tester.tap(find.text('保留最新'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await tester.pumpAndSettle();

    expect(client.deletedIds, ['oldest']);
    expect(find.text('已删除 1 个，失败 1 个'), findsOneWidget);
    expect(find.text('same.zip'), findsNWidgets(2));
  });

  testWidgets('全部加载且没有同名文件时显示空状态', (tester) async {
    final client = _CleanupClient(
      hasMore: false,
      files: [
        LzFile(id: 'a', name: 'a.zip', time: '今天', size: '1 M'),
        LzFile(id: 'b', name: 'b.zip', time: '昨天', size: '1 M'),
      ],
    );
    await _pumpDrive(tester, client);
    await _openCleanup(tester);

    expect(find.text('未找到同名文件'), findsOneWidget);
    expect(find.text('未加载全部内容，结果可能不全'), findsNothing);
    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    expect(deleteButton.onPressed, isNull);
  });
}
