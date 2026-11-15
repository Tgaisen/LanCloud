import 'dart:async';

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
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/drive_page.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

/// 第一页只有几条、且服务端说「还有下一页」的目录：真机上必须自动补一页，
/// 才能知道已经到底（否则要用户滑一下才出现「已加载全部」）。
class _FakeClient extends LanzouClient {
  _FakeClient() : super(uid: '1');

  final List<int> filePages = [];
  final List<String> filePageFolders = [];

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async {
    // 根目录里放一个子目录，用来测「进入目录」这条路径
    if (folderId == '-1') {
      return (
        folders: [LzFolder(id: 'sub', name: '子目录', desc: '')],
        path: const <PathNode>[],
      );
    }
    return (
      folders: const <LzFolder>[],
      path: [PathNode(id: folderId, name: '子目录')],
    );
  }

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async {
    filePages.add(page);
    filePageFolders.add(folderId);
    // 根目录：没有文件，也没有下一页
    if (folderId == '-1') {
      return (files: const <LzFile>[], hasMore: false);
    }
    if (page == 1) {
      return (
        files: [
          for (var i = 0; i < 3; i++)
            LzFile(id: 'l$i', name: 'f$i.zip', size: '1 M', time: ''),
        ],
        hasMore: true,
      );
    }
    // 第二页空 + hasMore=false：服务端说「到底了」
    return (files: const <LzFile>[], hasMore: false);
  }
}

/// 第一页足够长、且服务端明确还有下一页；搜索期间不应再补页。
class _IncompleteSearchClient extends LanzouClient {
  _IncompleteSearchClient() : super(uid: '1');

  final List<int> filePages = [];

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async => (folders: const <LzFolder>[], path: const <PathNode>[]);

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async {
    filePages.add(page);
    return page == 1
        ? (
            files: [
              for (var i = 0; i < 20; i++)
                LzFile(id: 'file$i', name: 'file$i.zip', size: '1 M', time: ''),
            ],
            hasMore: true,
          )
        : (files: const <LzFile>[], hasMore: false);
  }
}

class _LoadAllClient extends LanzouClient {
  _LoadAllClient() : super(uid: '1');

  final List<int> filePages = [];
  final Completer<({List<LzFile> files, bool hasMore})> secondPage =
      Completer<({List<LzFile> files, bool hasMore})>();
  final Completer<({List<LzFile> files, bool hasMore})> thirdPage =
      Completer<({List<LzFile> files, bool hasMore})>();

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async => (folders: const <LzFolder>[], path: const <PathNode>[]);

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) {
    filePages.add(page);
    return switch (page) {
      1 => Future.value((
        files: [
          for (var i = 0; i < 20; i++)
            LzFile(id: 'page1-$i', name: 'page1-$i.zip', size: '1 M', time: ''),
        ],
        hasMore: true,
      )),
      2 => secondPage.future,
      3 => thirdPage.future,
      _ => Future.value((files: const <LzFile>[], hasMore: false)),
    };
  }
}

/// 根目录内容足够长，用来验证从子目录返回时恢复滚动位置。
class _ScrollMemoryClient extends _FakeClient {
  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) {
    if (folderId == '-1') {
      return Future.value((
        files: [
          for (var i = 0; i < 30; i++)
            LzFile(id: 'root$i', name: 'root-$i.zip', size: '1 M', time: ''),
        ],
        hasMore: false,
      ));
    }
    return super.listFilesPage(folderId, page);
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

void main() {
  Future<void> openLoadAllRemaining(WidgetTester tester) async {
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载全部剩余内容'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('网盘搜索未加载全部分页时提示结果可能不全', (tester) async {
    final client = _IncompleteSearchClient();
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
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

    expect(client.filePages, [1]);
    expect(find.text(AppLocalizationsZh().searchIncomplete), findsNothing);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在的文件');
    await tester.pumpAndSettle();

    expect(find.text(AppLocalizationsZh().searchIncomplete), findsOneWidget);
    expect(client.filePages, [1]);

    await tester.enterText(find.byType(TextField), 'file0');
    await tester.pumpAndSettle();

    expect(find.text('file0.zip'), findsOneWidget);
    expect(find.text(AppLocalizationsZh().searchIncomplete), findsOneWidget);
    expect(client.filePages, [1]);
  });

  testWidgets('目录内容不满一屏时自动补页：进入即显示「已加载全部」', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(app, manager, client),
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const DrivePage(
            initialFolderId: 'sub',
            initialName: '子目录',
            tabIndex: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 自动补了第二页（不需要用户滑动）
    expect(client.filePages, contains(2));
    // 并且立刻显示「已加载全部」
    expect(find.text('f0.zip'), findsOneWidget);
    expect(find.text('已加载全部'), findsOneWidget);
  });

  // 下拉刷新会清掉目录缓存并强制重新联网拉第一页；这条路径同样要自动补页，
  // 否则刷新后又变成「看起来没到底」。
  testWidgets('下拉刷新后依然自动补页并显示「已加载全部」', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(app, manager, client),
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const DrivePage(
            initialFolderId: 'sub',
            initialName: '子目录',
            tabIndex: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已加载全部'), findsOneWidget);

    // 下拉刷新：清缓存 + 重新拉第一页
    client.filePages.clear();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1200,
    );
    await tester.pumpAndSettle();

    expect(client.filePages, contains(1));
    expect(client.filePages, contains(2));
    expect(find.text('已加载全部'), findsOneWidget);
  });

  // 真机上最常见的一条路径：从根目录点进子目录（走目录切换流程），
  // 切换期间的补页检查会被 _directorySwitching 挡住，切换结束后必须再补一次。
  testWidgets('从根目录进入子目录后也会自动补页并显示「已加载全部」', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp();
    // 关掉「最近使用」记录：测试环境没有数据库实现，进入目录时不必写库
    app.environment.settingsState.store.recentLimit = 0;
    final manager = buildTransferManagerForEnvironment(app.environment);
    addTearDown(app.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(app, manager, client),
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          // 从根目录开始，点进「子目录」验证目录切换这条路径
          home: const DrivePage(tabIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('子目录'), findsOneWidget);

    // 进入子目录：这里会经历 _animateDirectorySwitch + _load
    client.filePages.clear();
    client.filePageFolders.clear();
    await tester.tap(find.text('子目录'));
    await tester.pumpAndSettle();

    expect(
      client.filePageFolders,
      containsAll(<String>['sub']),
      reason: '进入子目录后应该请求该目录的分页',
    );
    expect(client.filePages, contains(2), reason: '内容不满一屏时要自动补第二页');
    expect(find.text('已加载全部'), findsOneWidget);
  });

  testWidgets('返回上级目录时保留滚动位置并展开顶栏', (tester) async {
    Future<void> pumpFrames() async {
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final client = _ScrollMemoryClient();
    final app = _FakeApp();
    app.environment.settingsState.store.recentLimit = 0;
    final manager = buildTransferManagerForEnvironment(app.environment);
    addTearDown(app.dispose);
    app.environment.settingsState.store.hideTopBar = true;
    tester.view.devicePixelRatio = 1.0;
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
    await pumpFrames();

    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(240);
    await pumpFrames();
    expect(app.environment.navigation.topBarHide.value, greaterThan(0));

    app.environment.drive.folderRequest.value = 'sub';
    await pumpFrames();
    expect(find.text('f0.zip'), findsOneWidget);

    await tester.tap(find.text('根目录'));
    await pumpFrames();

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      closeTo(240, 0.5),
    );
    expect(app.environment.navigation.topBarHide.value, 0);
  });

  testWidgets('加载全部剩余内容显示页数，取消时保留已完成页面并丢弃在途页', (tester) async {
    final client = _LoadAllClient();
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
    addTearDown(app.dispose);
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
    expect(client.filePages, [1]);

    await openLoadAllRemaining(tester);
    expect(find.text('已加载 1 页'), findsOneWidget);

    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('已加载 1 页'), findsNothing);

    client.secondPage.complete((
      files: [
        LzFile(id: 'page2-a', name: 'page2-a.zip', size: '1 M', time: ''),
        LzFile(id: 'page2-b', name: 'page2-b.zip', size: '1 M', time: ''),
      ],
      hasMore: true,
    ));
    await tester.pumpAndSettle();

    expect(client.filePages, [1, 2]);
    expect(app.environment.drive.cache.get('-1')?.files, hasLength(20));
    expect(app.environment.drive.cache.get('-1')?.page, 1);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    final loadAllTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('加载全部剩余内容'), matching: find.byType(ListTile)),
    );
    expect(loadAllTile.enabled, isTrue);
  });

  testWidgets('加载全部剩余内容逐页更新并在服务端结束后禁用入口', (tester) async {
    final client = _LoadAllClient();
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
    addTearDown(app.dispose);
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

    await openLoadAllRemaining(tester);
    client.secondPage.complete((
      files: [
        LzFile(id: 'page2-a', name: 'page2-a.zip', size: '1 M', time: ''),
        LzFile(id: 'page2-b', name: 'page2-b.zip', size: '1 M', time: ''),
      ],
      hasMore: true,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('已加载 2 页'), findsOneWidget);
    expect(client.filePages, [1, 2, 3]);

    client.thirdPage.complete((
      files: [
        LzFile(id: 'page3-end', name: 'page3-end.zip', size: '1 M', time: ''),
      ],
      hasMore: false,
    ));
    await tester.pumpAndSettle();

    final snapshot = app.environment.drive.cache.get('-1');
    expect(snapshot?.files, hasLength(23));
    expect(snapshot?.page, 3);
    expect(snapshot?.hasMore, isFalse);

    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    final loadAllTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('加载全部剩余内容'), matching: find.byType(ListTile)),
    );
    expect(loadAllTile.enabled, isFalse);
  });
}
