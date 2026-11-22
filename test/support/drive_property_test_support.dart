import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;

import 'transfer_test_support.dart' show buildTransferManagerForEnvironment;
export 'transfer_test_support.dart' show buildTransferManagerForEnvironment;

final testZh = AppLocalizationsZh();

/// 固定返回一个文件 + 一个文件夹，并给出可预测的分享信息。
///
/// 收藏 / 快速访问的选中态要读本地库，测试环境里没有 sqflite 插件，
/// 这里只覆盖「结构」：一行 5 个图标按钮 + 详情列表；选中态本身由
/// test/m3e_icon_button_group_test.dart 与真机验证覆盖。
class FakeDriveClient extends LanzouClient {
  FakeDriveClient() : super(uid: '1');

  static const String fileUrl = 'https://share.example/file-f1';
  static const String folderUrl = 'https://share.example/folder-fd1';

  /// 分享信息请求次数：用来验「属性弹窗取过一次后，下载 / 复制链接 /
  /// 二维码复用这份，不再各请求一次」。
  int shareFileCalls = 0;
  int shareFolderCalls = 0;

  /// 重命名与简介修改流程里实际调用的接口参数。
  final List<String> renamedFiles = <String>[];
  final List<String> renamedFolders = <String>[];
  final List<String> savedDescs = <String>[];
  final List<String> savedFolderDescs = <String>[];
  final List<({String id, bool isFile})> deletedItems = [];
  final List<({String id, String folderId})> movedFiles = [];

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId, {
    CancelToken? cancelToken,
  }) async => (
    folders: folderId == '-1'
        ? [LzFolder(id: 'fd1', name: '子文件夹', desc: '')]
        : const <LzFolder>[],
    path: const <PathNode>[],
  );

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page, {
    CancelToken? cancelToken,
  }) async => (
    files: folderId == '-1' && page == 1
        ? [
            LzFile(
              id: 'f1',
              name: 'a.zip',
              size: '1 M',
              time: '3 天前',
              downs: 3,
              hasPwd: true,
            ),
          ]
        : const <LzFile>[],
    hasMore: false,
  );

  @override
  Future<List<LzFile>> listFiles(
    String folderId, {
    CancelToken? cancelToken,
  }) async => const <LzFile>[];

  @override
  Future<String> fileDesc(String fileId, {CancelToken? cancelToken}) async =>
      '文件简介';

  @override
  Future<void> setFileName(
    String fileId,
    String name, {
    CancelToken? cancelToken,
  }) async => renamedFiles.add(name);

  @override
  Future<void> setDesc(
    String fileId,
    String desc, {
    CancelToken? cancelToken,
  }) async => savedDescs.add(desc);

  @override
  Future<void> renameFolder(
    String folderId,
    String name, {
    CancelToken? cancelToken,
  }) async => renamedFolders.add(name);

  @override
  Future<void> setFolderDesc(
    String folderId,
    String desc, {
    CancelToken? cancelToken,
  }) async => savedFolderDescs.add(desc);

  @override
  Future<void> deleteItem({
    required String id,
    required bool isFile,
    CancelToken? cancelToken,
  }) async {
    deletedItems.add((id: id, isFile: isFile));
  }

  @override
  Future<void> moveFile(
    String fileId,
    String folderId, {
    CancelToken? cancelToken,
  }) async {
    movedFiles.add((id: fileId, folderId: folderId));
  }

  @override
  Future<ShareInfo> shareInfoOfFile(
    String fileId, {
    bool withDetails = true,
    CancelToken? cancelToken,
  }) async {
    shareFileCalls += 1;
    return ShareInfo(
      url: fileUrl,
      pwd: 'abcd',
      isFile: true,
      name: 'a.zip',
      desc: '文件简介',
    );
  }

  @override
  Future<ShareInfo> shareInfoOfFolder(
    String folderId, {
    CancelToken? cancelToken,
  }) async {
    shareFolderCalls += 1;
    return ShareInfo(
      url: folderUrl,
      pwd: 'efgh',
      isFile: false,
      name: '子文件夹',
      desc: '文件夹简介',
    );
  }

  @override
  Future<({String size, int count, String name, String desc, String url})?>
  folderStats(String folderId, {CancelToken? cancelToken}) async =>
      (size: '2 M', count: 7, name: '子文件夹', desc: '文件夹简介', url: folderUrl);
}

class MemberRenameClient extends FakeDriveClient {
  @override
  Future<void> setFileName(
    String fileId,
    String name, {
    CancelToken? cancelToken,
  }) async {
    throw const LanzouException(
      'fallback',
      code: LanzouErrorCode.renameRequiresMembership,
    );
  }
}

class NoStatsClient extends FakeDriveClient {
  @override
  Future<({String size, int count, String name, String desc, String url})?>
  folderStats(String folderId, {CancelToken? cancelToken}) async => null;
}

class ManyFilesClient extends FakeDriveClient {
  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page, {
    CancelToken? cancelToken,
  }) async => (
    files: folderId == '-1' && page == 1
        ? [
            for (var i = 1; i <= 3; i++)
              LzFile(
                id: 'f$i',
                name: 'file$i.zip',
                size: '1 M',
                time: '1 天前',
                downs: 5,
                hasPwd: false,
              ),
          ]
        : const <LzFile>[],
    hasMore: false,
  );
}

class PartialBatchRenameClient extends ManyFilesClient {
  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId, {
    CancelToken? cancelToken,
  }) async => (
    folders: folderId == '-1'
        ? [LzFolder(id: 'fd1', name: 'file-folder', desc: '')]
        : const <LzFolder>[],
    path: const <PathNode>[],
  );

  @override
  Future<void> setFileName(
    String fileId,
    String name, {
    CancelToken? cancelToken,
  }) async {
    throw const LanzouException(
      'fallback',
      code: LanzouErrorCode.renameRequiresMembership,
    );
  }
}

class FakeDriveApp {
  FakeDriveApp(this._client, {LanzouClient? publicClient})
    : _public = publicClient ?? FakePublicClient();

  final AppEnvironment environment = AppEnvironment();
  final LanzouClient _client;
  final LanzouClient _public;

  void dispose() => environment.dispose();
}

/// 直链解析：默认立刻成功，测试里不打网络。
class FakePublicClient extends LanzouClient {
  FakePublicClient() : super(uid: '0');

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
    CancelToken? cancelToken,
  }) async => DirectFile(name: 'a.zip', url: 'https://cdn.example/a.zip');
}

/// 直链解析挂起：放行 / 放失败由测试决定。
class GatedPublicClient extends LanzouClient {
  GatedPublicClient() : super(uid: '0');

  final Completer<DirectFile> gate = Completer<DirectFile>();

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
    CancelToken? cancelToken,
  }) => gate.future;
}

/// 分享信息卡住不返回的客户端：用来验「数据没回来时按钮置灰」。
class GatedDriveClient extends FakeDriveClient {
  final Completer<ShareInfo> share = Completer<ShareInfo>();

  @override
  Future<ShareInfo> shareInfoOfFile(
    String fileId, {
    bool withDetails = true,
    CancelToken? cancelToken,
  }) => share.future;
}

/// 固定服务端时间升序顺序，用于验证升降序与文件夹特殊规则。
class OrderedDriveClient extends FakeDriveClient {
  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId, {
    CancelToken? cancelToken,
  }) async => (
    folders: folderId == '-1'
        ? [
            LzFolder(id: 'fb', name: '文件夹 B', desc: ''),
            LzFolder(id: 'fa', name: '文件夹 A', desc: ''),
            LzFolder(id: 'fc', name: '文件夹 C', desc: ''),
          ]
        : const <LzFolder>[],
    path: const <PathNode>[],
  );

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page, {
    CancelToken? cancelToken,
  }) async => (
    files: folderId == '-1' && page == 1
        ? [
            LzFile(
              id: 'f3',
              name: 'a.zip',
              size: '3 M',
              time: '3 天前',
              downs: 1,
            ),
            LzFile(
              id: 'f2',
              name: 'b.zip',
              size: '2 M',
              time: '2 天前',
              downs: 3,
            ),
            LzFile(
              id: 'f1',
              name: 'c.zip',
              size: '1 M',
              time: '1 天前',
              downs: 2,
            ),
          ]
        : const <LzFile>[],
    hasMore: false,
  );
}

/// 弹窗里那一行图标按钮：按 tooltip 找到对应按钮。
M3EToggleButton toggleButton(WidgetTester tester, String tooltip) => tester
    .widgetList<M3EToggleButton>(find.byType(M3EToggleButton))
    .firstWhere((button) => button.tooltip == tooltip);

/// 弹窗（面板）内的文字：页面本身也有「删除」等按钮，断言要限定在弹窗里。
Finder sheetText(String text) =>
    find.descendant(of: find.byType(M3EBottomSheet), matching: find.text(text));

/// 属性弹窗里的快捷操作按钮：页面里还有隐藏的多选条，tooltip 会重名。
Finder sheetTooltip(String label) => find.descendant(
  of: find.byType(M3EBottomSheet),
  matching: find.byTooltip(label),
);

Finder sheetToggleButtons() => find.descendant(
  of: find.byType(M3EBottomSheet),
  matching: find.byType(M3EToggleButton),
);

Finder menuRowText(String text) =>
    find.descendant(of: find.byType(M3eMenuRow), matching: find.text(text));

Finder adaptiveSheetAction(String text) => find.descendant(
  of: find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
  matching: find.text(text),
);

Finder adaptiveSheetTiles() => find.descendant(
  of: find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
  matching: find.byType(ListTile),
);

List<String> adaptiveSheetGroupLabels(WidgetTester tester, int index) => tester
    .widgetList<ListTile>(
      find.descendant(
        of: find.byKey(ValueKey('adaptive-m3e-menu-group-$index')),
        matching: find.byType(ListTile),
      ),
    )
    .map((tile) => (tile.title! as Text).data!)
    .toList();

Future<void> openPropertyMore(
  WidgetTester tester, {
  String label = '更多操作',
}) async {
  await tester.tap(sheetTooltip(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> pumpDrive(
  WidgetTester tester,
  FakeDriveApp app, {
  TransferManager? manager,
  String folderId = '-1',
  String folderName = '根目录',
  VisualDensity density = VisualDensity.standard,
  Size viewSize = const Size(420, 900),
  Locale locale = const Locale('zh'),
  bool freeTier = false,
  PlatformCapabilities capabilities = PlatformCapabilities.android,
}) async {
  final environment = app.environment;
  final transfers = manager ?? buildTransferManagerForEnvironment(environment);
  if (freeTier) {
    environment.accountState.store.accounts = [
      Account(uid: '1', cookie: 'cookie'),
    ];
    environment.accountState.store.activeUid = '1';
  } else {
    environment.accountState.store.activeUid = '';
  }
  addTearDown(app.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewSize;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transferManagerProvider.overrideWithValue(transfers),
        lanzouClientRegistryProvider.overrideWithValue(
          LanzouClientRegistry(
            factory: (uid) => uid == '0' ? app._public : app._client,
          ),
        ),
        accountStateProvider.overrideWithValue(environment.accountState),
        appDbProvider.overrideWithValue(environment.db),
        driveStateProvider.overrideWithValue(environment.drive),
        cachePageSettingsStateProvider.overrideWithValue(
          environment.cachePageSettings,
        ),
        listHomeSettingsStateProvider.overrideWithValue(
          environment.listHomeSettings,
        ),
        navigationAppearanceSettingsStateProvider.overrideWithValue(
          environment.navigationAppearanceSettings,
        ),
        navigationStateProvider.overrideWithValue(environment.navigation),
        platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
      child: MaterialApp(
        theme: ThemeData(visualDensity: density),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        // 和应用一致：强调排版 / 弹窗宽度这些组件级样式挂在 builder 上
        builder: (context, child) =>
            M3eComponentStyles(child: child ?? const SizedBox.shrink()),
        home: DrivePage(
          initialFolderId: folderId,
          initialName: folderName,
          tabIndex: 0,
        ),
      ),
    ),
  );
  // 列表入场动画 + 首帧异步加载：有界 pump，不用 settle（弹窗可能一直有
  // 加载指示在转）
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> openAddMenu(WidgetTester tester) async {
  await tester.tap(find.text(testZh.add));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// 打开一个弹窗：等进场动画播完（有界 pump）。
Future<void> settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
