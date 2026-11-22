import 'package:dio/dio.dart' show CancelToken;
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
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/m3e.dart';

import 'support/transfer_test_support.dart'
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
    String folderId, {
    CancelToken? cancelToken,
  }) async => (folders: const <LzFolder>[], path: const <PathNode>[]);

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page, {
    CancelToken? cancelToken,
  }) async => page == 1
      ? (files: files, hasMore: hasMore)
      : (files: const <LzFile>[], hasMore: false);

  @override
  Future<void> deleteItem({
    required String id,
    required bool isFile,
    CancelToken? cancelToken,
  }) async {
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

Future<void> _smoothDrag(
  WidgetTester tester,
  TestGesture gesture,
  double dy, {
  int steps = 10,
}) async {
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

int _selectedDuplicateCount(WidgetTester tester) {
  final items = tester.widgetList<Md3ListItem>(
    find.descendant(
      of: find.byType(M3EBottomSheet),
      matching: find.byType(Md3ListItem),
    ),
  );
  return items.where((item) => item.selected).length;
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

    final titleFinder = find.text('该目录下的同名文件');
    expect(titleFinder, findsOneWidget);
    final title = tester.widget<Text>(titleFinder);
    final titleContext = tester.element(titleFinder);
    expect(
      title.style?.fontWeight,
      titleContext.m3eEmphasizedTheme.titleLarge?.fontWeight,
    );
    expect(find.text('未加载全部内容，结果可能不全'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SectionHeader), matching: find.text('3')),
      findsOneWidget,
    );
    expect(find.text('共 1 组 3 个同名文件'), findsOneWidget);
    final segmentedList = tester.widget<SegmentedSliverList>(
      find.byType(SegmentedSliverList).first,
    );
    final scheme = Theme.of(
      tester.element(find.byType(SegmentedSliverList).first),
    ).colorScheme;
    expect(segmentedList.color, scheme.surfaceContainer);

    final deleteButton = tester.widget<M3eIconButton>(
      find.byKey(const ValueKey('same-name-delete')),
    );
    expect(deleteButton.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.byType(Checkbox),
      ),
      findsNothing,
    );

    await tester.tap(find.text('保留最新'));
    await tester.pump();
    expect(_selectedDuplicateCount(tester), 2);

    await tester.tap(find.byKey(const ValueKey('same-name-delete')));
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

  testWidgets('同名文件允许整组全部删除', (tester) async {
    final client = _CleanupClient(
      hasMore: false,
      files: [
        LzFile(id: 'newest', name: 'same.zip', time: '3 天前', size: '3 M'),
        LzFile(id: 'older', name: 'same.zip', time: '4 天前', size: '2 M'),
        LzFile(id: 'oldest', name: 'same.zip', time: '5 天前', size: '1 M'),
      ],
    );
    await _pumpDrive(tester, client);
    await _openCleanup(tester);

    await tester.tap(find.text('保留最新'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('same-name-file-newest')).last);
    await tester.pump();
    expect(_selectedDuplicateCount(tester), 3);

    await tester.tap(find.byKey(const ValueKey('same-name-delete')));
    await tester.pumpAndSettle();
    expect(find.text('将把选中的 3 个同名文件移入回收站，继续吗？'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      client.deletedIds,
      containsAll(<String>['newest', 'older', 'oldest']),
    );
  });

  testWidgets('大量同名文件使用懒加载列表', (tester) async {
    final client = _CleanupClient(
      hasMore: false,
      files: [
        for (var i = 0; i < 40; i++)
          LzFile(
            id: 'same-$i',
            name: 'same.zip',
            time: '${i + 1} 天前',
            size: '1 M',
          ),
      ],
    );
    await _pumpDrive(tester, client);
    await _openCleanup(tester);

    expect(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text('40'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Md3ListItem).evaluate().length, lessThan(40));

    final titleY = tester.getTopLeft(find.text('该目录下的同名文件')).dy;
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('该目录下的同名文件')).dy, titleY);
    expect(find.byKey(const ValueKey('same-name-cancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('same-name-delete')), findsOneWidget);
  });

  testWidgets('同名文件弹窗的列表与手柄拖拽均跟手，并在松手后回弹', (tester) async {
    final client = _CleanupClient(
      hasMore: false,
      files: [
        for (var i = 0; i < 40; i++)
          LzFile(
            id: 'same-$i',
            name: 'same.zip',
            time: '${i + 1} 天前',
            size: '1 M',
          ),
      ],
    );
    await _pumpDrive(tester, client);
    await _openCleanup(tester);

    final title = find.text('该目录下的同名文件');
    final initialY = tester.getTopLeft(title).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView).last),
    );
    await _smoothDrag(tester, gesture, 160);
    await tester.pump();
    final movedBy = tester.getTopLeft(title).dy - initialY;
    expect(movedBy, greaterThan(40));
    expect(movedBy, lessThanOrEqualTo(160), reason: '面板不应重复消费同一次滚动位移');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, closeTo(initialY, 1));
    final sheet = tester.getRect(find.byType(M3EBottomSheet));
    final handleGesture = await tester.startGesture(
      Offset(sheet.center.dx, sheet.top + 24),
    );
    await _smoothDrag(tester, handleGesture, 160);
    await tester.pump();
    expect(tester.getTopLeft(title).dy, greaterThan(initialY + 40));

    await handleGesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, closeTo(initialY, 1));
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
    await tester.tap(find.byKey(const ValueKey('same-name-delete')));
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
    final deleteButton = tester.widget<M3eIconButton>(
      find.byKey(const ValueKey('same-name-delete')),
    );
    expect(deleteButton.onPressed, isNull);
  });
}
