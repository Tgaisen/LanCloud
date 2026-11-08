import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/legal_dialog.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

/// 固定返回一个文件 + 一个文件夹，并给出可预测的分享信息。
///
/// 收藏 / 快速访问的选中态要读本地库，测试环境里没有 sqflite 插件，
/// 这里只覆盖「结构」：一行 5 个图标按钮 + 详情列表；选中态本身由
/// test/m3e_icon_button_group_test.dart 与真机验证覆盖。
class _FakeClient extends LanzouClient {
  _FakeClient() : super(uid: '1');

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
    String folderId,
  ) async => (
    folders: folderId == '-1'
        ? [LzFolder(id: 'fd1', name: '子文件夹', desc: '')]
        : const <LzFolder>[],
    path: const <PathNode>[],
  );

  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async => (
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
  Future<List<LzFile>> listFiles(String folderId) async => const <LzFile>[];

  @override
  Future<String> fileDesc(String fileId) async => '文件简介';

  @override
  Future<void> setFileName(String fileId, String name) async =>
      renamedFiles.add(name);

  @override
  Future<void> setDesc(String fileId, String desc) async =>
      savedDescs.add(desc);

  @override
  Future<void> renameFolder(String folderId, String name) async =>
      renamedFolders.add(name);

  @override
  Future<void> setFolderDesc(String folderId, String desc) async =>
      savedFolderDescs.add(desc);

  @override
  Future<void> deleteItem({required String id, required bool isFile}) async {
    deletedItems.add((id: id, isFile: isFile));
  }

  @override
  Future<void> moveFile(String fileId, String folderId) async {
    movedFiles.add((id: fileId, folderId: folderId));
  }

  @override
  Future<ShareInfo> shareInfoOfFile(
    String fileId, {
    bool withDetails = true,
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
  Future<ShareInfo> shareInfoOfFolder(String folderId) async {
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
  folderStats(String folderId) async =>
      (size: '2 M', count: 7, name: '子文件夹', desc: '文件夹简介', url: folderUrl);
}

class _MemberRenameClient extends _FakeClient {
  @override
  Future<void> setFileName(String fileId, String name) async {
    throw const LanzouException(
      'fallback',
      code: LanzouErrorCode.renameRequiresMembership,
    );
  }
}

class _ManyFilesClient extends _FakeClient {
  @override
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async => (
    files: folderId == '-1' && page == 1
        ? [
            for (var i = 1; i <= 3; i++)
              LzFile(
                id: 'f$i',
                name: 'file$i.zip',
                size: '1 M',
                time: '',
                downs: 0,
                hasPwd: false,
              ),
          ]
        : const <LzFile>[],
    hasMore: false,
  );
}

class _PartialBatchRenameClient extends _ManyFilesClient {
  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async => (
    folders: folderId == '-1'
        ? [LzFolder(id: 'fd1', name: 'file-folder', desc: '')]
        : const <LzFolder>[],
    path: const <PathNode>[],
  );

  @override
  Future<void> setFileName(String fileId, String name) async {
    throw const LanzouException(
      'fallback',
      code: LanzouErrorCode.renameRequiresMembership,
    );
  }
}

class _FakeApp {
  _FakeApp(this._client, {LanzouClient? publicClient})
    : _public = publicClient ?? _FakePublic();

  final AppEnvironment environment = AppEnvironment();
  final LanzouClient _client;
  final LanzouClient _public;

  void dispose() => environment.dispose();
}

/// 直链解析：默认立刻成功，测试里不打网络。
class _FakePublic extends LanzouClient {
  _FakePublic() : super(uid: '0');

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async => DirectFile(name: 'a.zip', url: 'https://cdn.example/a.zip');
}

/// 直链解析挂起：放行 / 放失败由测试决定。
class _GatedPublic extends LanzouClient {
  _GatedPublic() : super(uid: '0');

  final Completer<DirectFile> gate = Completer<DirectFile>();

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) => gate.future;
}

/// 分享信息卡住不返回的客户端：用来验「数据没回来时按钮置灰」。
class _GatedClient extends _FakeClient {
  final Completer<ShareInfo> share = Completer<ShareInfo>();

  @override
  Future<ShareInfo> shareInfoOfFile(String fileId, {bool withDetails = true}) =>
      share.future;
}

/// 弹窗里那一行图标按钮：按 tooltip 找到对应按钮。
M3EToggleButton _toggleButton(WidgetTester tester, String tooltip) => tester
    .widgetList<M3EToggleButton>(find.byType(M3EToggleButton))
    .firstWhere((button) => button.tooltip == tooltip);

/// 弹窗（面板）内的文字：页面本身也有「删除」等按钮，断言要限定在弹窗里。
Finder _sheetText(String text) =>
    find.descendant(of: find.byType(M3EBottomSheet), matching: find.text(text));

/// 属性弹窗里的快捷操作按钮：页面里还有隐藏的多选条，tooltip 会重名。
Finder _sheetTooltip(String label) => find.descendant(
  of: find.byType(M3EBottomSheet),
  matching: find.byTooltip(label),
);

Finder _menuRowText(String text) =>
    find.descendant(of: find.byType(M3eMenuRow), matching: find.text(text));

Future<void> _openPropertyMore(
  WidgetTester tester, {
  String label = '更多操作',
}) async {
  await tester.tap(_sheetTooltip(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _pumpDrive(
  WidgetTester tester,
  _FakeApp app, {
  TransferManager? manager,
  String folderId = '-1',
  String folderName = '根目录',
  VisualDensity density = VisualDensity.standard,
  Size viewSize = const Size(420, 900),
  Locale locale = const Locale('zh'),
  bool freeTier = false,
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

/// 打开一个弹窗：等进场动画播完（有界 pump）。
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('网盘列表模式在宽窗口下仍保持单列', (tester) async {
    final app = _FakeApp(_ManyFilesClient());
    app.environment.cachePageSettings.store.gridView = false;
    await _pumpDrive(tester, app, viewSize: const Size(1200, 800));

    final first = tester.getTopLeft(find.text('file1.zip'));
    final second = tester.getTopLeft(find.text('file2.zip'));
    final third = tester.getTopLeft(find.text('file3.zip'));
    expect(second.dx, first.dx);
    expect(third.dx, first.dx);
    expect(second.dy, greaterThan(first.dy));
    expect(third.dy, greaterThan(second.dy));
    expect(find.byType(AdaptiveSliverRows), findsNothing);
  });

  testWidgets('网盘条目鼠标右键：菜单从鼠标坐标展开', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);
    final file = find.text('a.zip');
    final pointer = tester.getCenter(file);

    await tester.tap(
      file,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final menu = tester.getRect(find.byKey(const ValueKey('m3e-menu-card')));
    expect(menu.topLeft, pointer);
    expect(find.byType(M3eMenuRow), findsWidgets);
  });

  testWidgets('网盘页文件 ⋯ 菜单：重命名与简介拆分，属性打开属性弹窗', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件操作'));
    // ⋯ 菜单是弹簧展开的：pump 到它长出来（真机一两帧，测试里有界多给点）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    const order = ['下载', '属性', '复制链接', '访问密码', '移动', '重命名', '修改简介'];
    expect(find.byType(M3eMenuRow), findsNWidgets(order.length));
    for (final label in order) {
      // 页面本身也有「删除」这类文案，断言限定在菜单行里
      expect(
        find.descendant(
          of: find.byType(M3eMenuRow),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    // 顺序：下载 / 属性 / 复制链接 / 访问密码 / 移动 / 重命名 / 修改简介 / 删除
    final tops = [
      for (final label in order)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(M3eMenuRow),
                matching: find.text(label),
              ),
            )
            .dy,
    ];
    for (int i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '「${order[i]}」要排在「${order[i - 1]}」下面',
      );
    }
    // M3E vertical menu：项目是各自独立的圆角块，之间留 4dp 间隔
    final rows = find.byType(M3eMenuRow).evaluate().toList();
    for (int i = 1; i < rows.length; i++) {
      final above = tester.getRect(find.byType(M3eMenuRow).at(i - 1));
      final below = tester.getRect(find.byType(M3eMenuRow).at(i));
      expect(
        below.top - above.bottom,
        4,
        reason: '第 ${i + 1} 项与上一项之间应是 4dp 间隔',
      );
    }
    // 项目本身的圆角 12dp（卡片 16 − 左右内缩 4）
    final item = tester.widget<MenuItemButton>(
      find.byType(MenuItemButton).first,
    );
    final shape =
        item.style?.shape?.resolve(<WidgetState>{}) as RoundedRectangleBorder?;
    expect(
      (shape?.borderRadius as BorderRadius?)?.topLeft.x,
      12,
      reason: '菜单项目圆角应为 12dp',
    );
    expect(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.byIcon(Icons.input_field),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.byIcon(Icons.description_outlined),
      ),
      findsOneWidget,
    );

    // 第八项在默认窗口高度下需要滚动才会构建；滚到底验证“删除”仍在最后。
    final menuCard = find.byKey(const ValueKey('m3e-menu-card'));
    await tester.drag(menuCard, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('删除')),
      findsOneWidget,
    );
    await tester.drag(menuCard, const Offset(0, 120));
    await tester.pumpAndSettle();

    // 点「属性」→ 打开文件属性弹窗（那一行 5 个图标按钮）
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('属性')),
    );
    await _settleSheet(tester);
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    expect(_sheetText('类型'), findsOneWidget);
    expect(_sheetText('ZIP 文件'), findsOneWidget);
    expect(_sheetText('重命名'), findsNothing);
    expect(_sheetTooltip('更多操作'), findsOneWidget);
  });

  testWidgets('网盘页文件菜单：下载入队，重复下载提示跳过', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    final manager = buildTransferManagerForEnvironment(app.environment);
    await _pumpDrive(tester, app, manager: manager);

    Future<void> openMenuAndTapDownload() async {
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(
        find.descendant(of: find.byType(M3eMenuRow), matching: find.text('下载')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openMenuAndTapDownload();
    expect(client.shareFileCalls, 1);
    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single.refId, ':f1');
    expect(find.text('已开始下载'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await openMenuAndTapDownload();
    expect(client.shareFileCalls, 1);
    expect(manager.tasks, hasLength(1));
    expect(find.text('已跳过：文件已在传输列表'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('网盘页文件 ⋯ 菜单：复制链接复制的是分享链接（带提取码）', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _pumpDrive(tester, app);
    await tester.tap(find.byTooltip('文件操作'));
    // ⋯ 菜单是弹簧展开的：pump 到它长出来
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('复制链接')),
    );
    await tester.pumpAndSettle();

    // 和属性弹窗一样：现取分享信息，把链接（含提取码）写进剪贴板
    expect(client.shareFileCalls, 1);
    expect(clipboard, hasLength(1));
    final copied = '${(clipboard.single.arguments as Map)['text']}';
    expect(copied, contains(_FakeClient.fileUrl));
    expect(copied, contains('abcd'));
  });

  testWidgets('网盘单条目菜单使用 Riverpod 客户端', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('复制链接')),
    );
    await tester.pumpAndSettle();

    expect(client.shareFileCalls, 1);
    expect(clipboard, hasLength(1));

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    expect(client.shareFileCalls, 2);
    expect(_toggleButton(tester, '复制链接').enabled, isTrue);
    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('重命名'));
    await _settleSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      'b.zip',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await _settleSheet(tester);
    expect(_sheetText('b.zip'), findsOneWidget);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('修改简介'));
    await _settleSheet(tester);
    await tester.enterText(find.byType(TextField), '新简介');
    await tester.tap(find.text('确定'));
    await _settleSheet(tester);

    expect(client.renamedFiles, ['b.zip']);
    expect(client.savedDescs, ['新简介']);

    // 八项菜单的「删除」需要滚到末尾，等提示条消失后再打开，避免点击被遮挡。
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    Navigator.of(tester.element(find.byType(DrivePage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('文件操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final menuCard = find.byKey(const ValueKey('m3e-menu-card'));
    await tester.drag(menuCard, const Offset(0, -200));
    await tester.pumpAndSettle();
    final deleteItem = find.descendant(
      of: find.byType(M3eMenuRow),
      matching: find.text('删除'),
    );
    await tester.tap(deleteItem);
    await _settleSheet(tester);
    expect(find.text('删除确认'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.deletedItems, [(id: 'f1', isFile: true)]);
  });

  testWidgets('网盘批量操作使用 Riverpod 客户端', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _pumpDrive(tester, app);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('复制链接'));
    await tester.pumpAndSettle();

    expect(client.shareFileCalls, 1);
    expect(clipboard, hasLength(1));
    // 等复制提示条消失，避免它盖住底部多选操作栏。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.deletedItems, [(id: 'f1', isFile: true)]);
  });

  testWidgets('网盘多选：操作栏顺序与批量重命名预览生效', (tester) async {
    final client = _ManyFilesClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.longPress(find.text('file1.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('file2.zip'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<BatchAction>(find.byType(BatchAction))
          .map((action) => action.label),
      ['下载', '复制链接', '收藏', '删除', '更多'],
    );

    await tester.tap(find.byTooltip('更多'));
    await _settleSheet(tester);
    const moreOrder = ['访问密码', '移动', '重命名', '修改简介'];
    final moreTops = [
      for (final label in moreOrder)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(M3EBottomSheet),
                matching: find.text(label),
              ),
            )
            .dy,
    ];
    for (var i = 1; i < moreTops.length; i++) {
      expect(moreTops[i], greaterThan(moreTops[i - 1]), reason: moreOrder[i]);
    }

    await tester.tap(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.text('重命名'),
      ),
    );
    await _settleSheet(tester);
    expect(
      find.byKey(const ValueKey('drive-batch-rename-supporting-text')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-search')),
      'file',
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-replacement')),
      'doc',
    );
    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-preview')));
    await _settleSheet(tester);
    expect(find.text('file1.zip → doc1.zip'), findsOneWidget);
    expect(find.text('file2.zip → doc2.zip'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(client.renamedFiles, ['doc1.zip', 'doc2.zip']);
    expect(find.text('doc1.zip'), findsOneWidget);
    expect(find.text('doc2.zip'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('网盘批量重命名：文件失败时文件夹仍成功并汇总', (tester) async {
    final client = _PartialBatchRenameClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app, freeTier: true);

    await tester.longPress(find.text('file1.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('file-folder'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await _settleSheet(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.text('重命名'),
      ),
    );
    await _settleSheet(tester);
    expect(
      find.byKey(const ValueKey('drive-batch-rename-supporting-text')),
      findsOneWidget,
    );
    expect(find.text('修改文件名称需开通会员'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-search')),
      'file',
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-replacement')),
      'doc',
    );
    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-preview')));
    await _settleSheet(tester);
    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(client.renamedFolders, ['doc-folder']);
    expect(find.text('doc-folder'), findsOneWidget);
    expect(find.text('file1.zip'), findsOneWidget);
    expect(find.text('已重命名 1 个条目，1 个失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('已添加下载的文件：属性弹窗下载按钮 checked，点击弹五项菜单', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    final manager = buildTransferManagerForEnvironment(app.environment);
    // 与页面一致的任务 refId：app.activeUid 在测试里是空串
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'a.zip',
          accountUid: '',
          refId: ':f1',
        )
        ..status = TransferStatus.done
        ..savedPath = '/tmp/a.zip',
    );

    await _pumpDrive(tester, app, manager: manager);
    // 列表卡片上先有「已加入下载」小标记
    expect(find.byIcon(Icons.download_done), findsOneWidget);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    // 下载按钮变 checked、tooltip 变「已加入下载」
    expect(_toggleButton(tester, '已加入下载').checked, isTrue);

    // 点它弹二级菜单：已完成 → 打开 / 分享可用，取消位换成删除记录，
    // 重新下载与「删除记录与文件」也可用
    await tester.tap(find.byTooltip('已加入下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final rows = tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .toList();
    expect(rows.map((r) => r.label).toList(), [
      '打开',
      '分享',
      '删除此条记录',
      '删除记录与文件',
      '重新下载',
    ]);
    expect(rows.every((r) => r.enabled), isTrue);

    // 删除这条任务记录：标记消失，按钮回到未选中（tooltip 变回「下载」）
    await tester.tap(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('删除此条记录'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(manager.tasks, isEmpty);
    expect(_toggleButton(tester, '下载').checked, isFalse);
  });

  testWidgets('已添加下载的文件：菜单「删除记录与文件」连带删掉本地文件并恢复未下载', (tester) async {
    final app = _FakeApp(_FakeClient());
    final manager = buildTransferManagerForEnvironment(app.environment);
    final dir = Directory.systemTemp.createTempSync('lancloud-del-mark');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/a.zip')..writeAsStringSync('x');
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'a.zip',
          accountUid: '',
          refId: ':f1',
        )
        ..status = TransferStatus.done
        ..savedPath = file.path,
    );

    await _pumpDrive(tester, app, manager: manager);
    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await tester.tap(find.byTooltip('已加入下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('删除记录与文件'),
      ),
    );
    // 点击 → 菜单收起（post-frame 回调）→ 选择回调里删文件、删记录
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(manager.tasks, isEmpty);
    // 文件是后台真实 I/O 删的：让真实事件循环跑两轮再回假时钟刷新续体
    for (var i = 0; i < 3 && file.existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(file.existsSync(), isFalse);
    // 恢复未下载原状
    expect(_toggleButton(tester, '下载').checked, isFalse);
  });

  testWidgets('已添加下载但失败：属性弹窗显示「下载失败」+ 下载关闭图标', (tester) async {
    final app = _FakeApp(_FakeClient());
    final manager = buildTransferManagerForEnvironment(app.environment);
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'a.zip',
          accountUid: '',
          refId: ':f1',
        )
        ..status = TransferStatus.failed
        ..error = '网络错误',
    );
    await _pumpDrive(tester, app, manager: manager);
    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    expect(_toggleButton(tester, '下载失败').checked, isTrue);
    // 弹窗里的图标位换成「下载关闭」（列表徽标仍是 download_done）
    expect(find.byIcon(Icons.file_download_off), findsOneWidget);
  });

  testWidgets('网盘文件属性弹窗：点下载先显示解析中环，解析失败恢复原状', (tester) async {
    final shareGate = _GatedClient();
    final directGate = _GatedPublic();
    final app = _FakeApp(shareGate, publicClient: directGate);
    await _pumpDrive(tester, app);
    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    // 分享信息回来之前：下载按钮置灰（原有行为）
    expect(_toggleButton(tester, '下载').enabled, isFalse);
    shareGate.share.complete(
      ShareInfo(
        url: _FakeClient.fileUrl,
        pwd: 'abcd',
        isFile: true,
        name: 'a.zip',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_toggleButton(tester, '下载').enabled, isTrue);

    // 直链解析挂住：按钮位显示不确定态环 + 「解析中」（文案取 l10n，
    // 避免写死后被改文案带崩）
    final resolving = AppLocalizations.of(
      tester.element(find.byType(DrivePage)),
    ).resolving;
    // 页面里还有隐藏的多选条（同一个 tooltip），限定在属性弹窗里点
    await tester.tap(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.byTooltip('下载'),
      ),
    );
    await tester.pump();
    expect(find.byTooltip(resolving), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      isNull,
    );

    // 解析失败：回到「下载」原状（没有任务、没有环）
    directGate.gate.completeError(const LanzouException('网络异常'));
    await tester.pump();
    await tester.pump();
    expect(_toggleButton(tester, '下载').enabled, isTrue);
    expect(find.byTooltip(resolving), findsNothing);
  });

  testWidgets('网盘文件属性弹窗：点「重新下载」立刻进入解析中状态', (tester) async {
    final directGate = _GatedPublic();
    final app = _FakeApp(_FakeClient(), publicClient: directGate);
    final manager = buildTransferManagerForEnvironment(app.environment);
    manager.tasks.add(
      TransferTask(
        id: 'd1',
        kind: TransferKind.download,
        name: 'a.zip',
        accountUid: '',
        refId: ':f1',
      )..status = TransferStatus.failed,
    );
    await _pumpDrive(tester, app, manager: manager);
    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    await tester.tap(find.byTooltip('下载失败'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('重新下载')),
    );
    // 点击 → 菜单收起（post-frame 回调）→ 选择回调里删旧任务并开始解析
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 旧任务已删、新任务还没入队：按钮位立刻换成不确定态环
    final resolving = AppLocalizations.of(
      tester.element(find.byType(DrivePage)),
    ).resolving;
    expect(manager.tasks, isEmpty);
    expect(find.byTooltip(resolving), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      isNull,
    );

    // 解析失败：恢复「下载」原状
    directGate.gate.completeError(const LanzouException('网络异常'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip(resolving), findsNothing);
    expect(_toggleButton(tester, '下载').enabled, isTrue);
  });

  testWidgets('宽屏：新建文件夹弹窗宽度固定，不超过 M3 上限 560', (tester) async {
    final app = _FakeApp(_FakeClient());
    // 宽屏（横屏 / 桌面）：以前弹窗会跟着输入内容一路变宽
    await _pumpDrive(tester, app, viewSize: const Size(1200, 700));

    await tester.tap(find.text('添加'));
    await _settleSheet(tester);
    await tester.tap(find.text('新建文件夹'));
    await _settleSheet(tester);
    // 自动聚焦 → 帧后量位置 → 180ms 上移动画：多给几帧让它走完
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(AlertDialog), findsOneWidget);
    // 页面顶栏还有搜索框，这里只看弹窗里的那个
    final Finder field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    // 新建文件夹弹窗带「名称 + 简介」两个输入框
    expect(field, findsNWidgets(2));
    // AlertDialog 的 RenderObject 是外层全屏 padding，量对话框本体要看内容的
    // 最近 Material 祖先（弹窗卡片）
    final Finder dialogCard = find
        .ancestor(of: field.first, matching: find.byType(Material))
        .first;
    final double width = tester.getSize(dialogCard).width;
    expect(width, lessThanOrEqualTo(560), reason: 'M3 弹窗上限 560dp');
    expect(width, greaterThan(400), reason: '宽屏下应贴近上限，而不是按内容缩着');

    // 输入很长的名字：宽度不该抽动（TextField 的固有宽度会随文本变）
    await tester.enterText(field.first, '这是一个很长很长的文件夹名字用来验证弹窗宽度不会抽动');
    await tester.pump();
    expect(tester.getSize(dialogCard).width, width);
  });

  testWidgets('横屏 + 输入法：新建文件夹弹窗里的输入框仍在弹窗内可见', (tester) async {
    final app = _FakeApp(_FakeClient());
    // 横屏手机真实尺寸：792×368（NOH-AN00），微信输入法实测占 251dp →
    // 可用高度只剩 117dp，装不下「输入框 56 + 操作行 72」
    await _pumpDrive(tester, app, viewSize: const Size(792, 368));
    tester.view.viewInsets = const FakeViewPadding(bottom: 251);
    addTearDown(tester.view.reset);

    await tester.tap(find.text('添加'));
    await _settleSheet(tester);
    await tester.tap(find.text('新建文件夹'));
    await _settleSheet(tester);

    // 自动聚焦 → 帧后量位置 → 180ms 上移动画：多给几帧让它走完
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // 紧凑形态下不再是 AlertDialog（内容和操作在同一个滚动区里），
    // 页面本身没有输入框，直接按类型找即可
    final Finder field = find.byType(TextField);
    expect(field, findsNWidgets(2), reason: '名称 + 简介两个输入框');
    final Finder card = find
        .ancestor(of: field.first, matching: find.byType(Material))
        .first;
    final Rect cardRect = tester.getRect(card);
    final Rect fieldRect = tester.getRect(field.first);

    expect(cardRect.height, greaterThan(0), reason: '弹窗本体不能被压没');
    expect(fieldRect.height, greaterThan(0), reason: '输入框要有高度');
    expect(
      cardRect.contains(fieldRect.center),
      isTrue,
      reason: '输入框不能被挤出弹窗（以前会被挤到看不见）',
    );
    expect(
      fieldRect.bottom,
      lessThanOrEqualTo(368 - 251 + 0.5),
      reason: '输入框要在输入法上方可见',
    );
  });

  testWidgets('竖屏 + 输入法：弹窗上移到剩余区域中间', (tester) async {
    final app = _FakeApp(_FakeClient());
    // 竖屏手机：393×852，输入法占 300dp → 剩余区域高 552dp，弹窗放得下
    await _pumpDrive(tester, app, viewSize: const Size(393, 852));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    await tester.tap(find.text('添加'));
    await _settleSheet(tester);
    await tester.tap(find.text('新建文件夹'));
    await _settleSheet(tester);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final Finder field = find.byType(TextField);
    final Finder card = find
        .ancestor(of: field.first, matching: find.byType(Material))
        .first;
    final Rect cardRect = tester.getRect(card);
    // 自然居中位置（852/2）上移半个键盘高度（150）→ 落在剩余区域 (0..552) 中心
    expect(
      cardRect.center.dy,
      closeTo((852 - 300) / 2, 1),
      reason: '弹窗应在输入法上方的剩余区域里居中',
    );
  });

  testWidgets('底部弹窗：键盘弹出时面板高度不缩（底部安全区按 viewPadding 稳定）', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app, viewSize: const Size(393, 852));
    // 系统导航栏 39dp：无键盘时 padding / viewPadding 都是 39
    tester.view.viewPadding = const FakeViewPadding(bottom: 39);
    tester.view.padding = const FakeViewPadding(bottom: 39);
    addTearDown(tester.view.reset);

    await tester.tap(find.text('添加'));
    await _settleSheet(tester);
    final double withoutKeyboard = tester
        .getSize(find.byType(M3EBottomSheet))
        .height;

    // 键盘弹出：padding.bottom 归零（导航栏被输入法盖住），viewInsets 顶上
    tester.view.padding = const FakeViewPadding();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.getSize(find.byType(M3EBottomSheet)).height,
      withoutKeyboard,
      reason: '键盘弹出时底部弹窗不应矮一截（切换账号 → Cookie 登录弹窗那个 bug）',
    );
  });

  testWidgets('宽屏：用户协议弹窗宽度也被 560 夹住', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app, viewSize: const Size(1200, 700));

    // 与应用里一样，从页面 context 打开协议弹窗
    unawaited(
      showLegalDialog(tester.element(find.byType(DrivePage)), LegalDoc.privacy),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.byType(FilledButton),
                  matching: find.byType(Material),
                )
                .first,
          )
          .width,
      lessThanOrEqualTo(560),
    );
  });

  testWidgets('桌面端紧凑密度：菜单首尾贴近卡片内边距', (tester) async {
    final app = _FakeApp(_FakeClient());
    // Windows 桌面默认 visualDensity.compact：行高被压到 40dp 而不是 48dp。
    // 卡片高度如果按 48dp 硬算，完全展开时底部就会多出一截空白。
    await _pumpDrive(tester, app, density: VisualDensity.compact);

    await tester.tap(find.byTooltip('文件操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    final menuCard = find.byKey(const ValueKey('m3e-menu-card'));
    final Rect card = tester.getRect(menuCard);
    final rows = find.byType(M3eMenuRow);
    final Rect first = tester.getRect(rows.first);
    expect(first.height, 40, reason: '紧凑密度下 MenuItemButton 行高 40dp');
    expect(first.top - card.top, 4, reason: '首项到卡片顶边也是 4dp');

    await tester.drag(menuCard, const Offset(0, -400));
    await tester.pumpAndSettle();
    final Rect last = tester.getRect(find.byType(M3eMenuRow).last);
    expect(last.height, 40, reason: '滚动后末项仍保持紧凑行高');
    expect(card.bottom - last.bottom, 4, reason: '末项到卡片底边也是 4dp');
  });

  testWidgets('文件属性弹窗：快捷操作与详情分层，低频操作收进更多菜单', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    // 一行 5 个纯图标按钮：下载 / 复制链接 / 二维码 / 收藏 / 更多操作
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    for (final tooltip in ['下载', '复制链接', '显示二维码', '添加收藏', '更多操作']) {
      expect(_toggleButton(tester, tooltip), isNotNull, reason: tooltip);
    }

    // 详细信息按「标签在上、值在下」集中为一个列表组。
    expect(_sheetText('类型'), findsOneWidget);
    expect(_sheetText('ZIP 文件'), findsOneWidget);
    expect(_sheetText('大小'), findsOneWidget);
    expect(_sheetText('1.0 MB'), findsOneWidget);
    expect(_sheetText('时间'), findsOneWidget);
    expect(_sheetText('3 天前'), findsOneWidget);
    expect(_sheetText('下载数'), findsOneWidget);
    expect(_sheetText('3'), findsOneWidget);
    expect(_sheetText('访问密码'), findsOneWidget);
    expect(_sheetText('已启用'), findsOneWidget);

    // 低频动作不再直接铺在属性页里。
    expect(_sheetText('重命名'), findsNothing);
    expect(_sheetText('修改简介'), findsNothing);
    expect(_sheetText('移动'), findsNothing);
    expect(_sheetText('删除'), findsNothing);
    // 「打开链接」入口已删（提示条里的复制链接等照旧）
    expect(_sheetText('打开链接'), findsNothing);

    // 更多菜单复用条目菜单，但去掉快捷按钮里已有的动作和“属性”自身。
    await _openPropertyMore(tester);
    const moreOrder = ['访问密码', '移动', '重命名', '修改简介', '删除'];
    expect(find.byType(M3eMenuRow), findsNWidgets(moreOrder.length));
    for (final label in moreOrder) {
      expect(_menuRowText(label), findsOneWidget, reason: label);
    }
    expect(_menuRowText('属性'), findsNothing);
    expect(_menuRowText('下载'), findsNothing);
    expect(_menuRowText('复制链接'), findsNothing);
  });

  testWidgets('文件属性弹窗：移动取消保留弹窗，确认成功后再关闭', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('移动'));
    await _settleSheet(tester);
    expect(find.text('选择目标文件夹'), findsOneWidget);
    expect(find.byType(M3EBottomSheet), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await _settleSheet(tester);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(client.movedFiles, isEmpty);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('移动'));
    await _settleSheet(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final moveHere = find.widgetWithText(FilledButton, '移动到此');
    expect(tester.widget<FilledButton>(moveHere).onPressed, isNotNull);
    await tester.tap(moveHere);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(client.movedFiles, [(id: 'f1', folderId: '-1')]);
    expect(find.byType(M3EBottomSheet), findsNothing);
  });

  testWidgets('文件属性弹窗：删除取消保留弹窗，确认成功后再关闭', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('删除'));
    await _settleSheet(tester);
    expect(find.text('删除确认'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await _settleSheet(tester);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(client.deletedItems, isEmpty);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('删除'));
    await _settleSheet(tester);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(client.deletedItems, [(id: 'f1', isFile: true)]);
    expect(find.byType(M3EBottomSheet), findsNothing);
  });

  testWidgets('文件属性弹窗：复制链接弹出 MD3E 菜单（分享链接 / 下载直链）', (tester) async {
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await tester.tap(_sheetTooltip('复制链接'));
    await _settleSheet(tester);
    // 菜单是弹簧展开的：等它长出来再断言（真机上就是一两帧的事）
    await tester.pumpAndSettle();

    // 菜单是贴在被点那一段下面的弹出菜单：属性弹窗还在，菜单浮在它上面
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    expect(find.byType(M3eMenuRow), findsNWidgets(2));
    expect(find.text('复制分享链接'), findsOneWidget);
    expect(find.text('复制下载直链'), findsOneWidget);

    // 菜单左缘跟着被点的那一段（而不是整个按钮组），并且贴着它的下边缘
    final Rect button = tester.getRect(_sheetTooltip('复制链接'));
    final Rect item = tester.getRect(find.byType(M3eMenuRow).first);
    expect(
      (item.left - button.left).abs(),
      lessThan(24),
      reason: '菜单左缘要对准被点的那一段',
    );
    expect(item.top, greaterThan(button.bottom), reason: '菜单要贴在那一段下方');

    await tester.tap(find.text('复制下载直链'));
    await _settleSheet(tester);
    expect(clipboard, hasLength(1));
    expect(
      '${(clipboard.single.arguments as Map)['text']}',
      'https://cdn.example/a.zip',
    );
  });

  testWidgets('文件属性弹窗：收藏态没加载出来前，收藏按钮置灰', (tester) async {
    final client = _GatedClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    // 分享信息（收藏判定要用它的链接）还没回来：收藏按钮不可点，
    // 否则会在状态未知时点出「重复收藏 / 错误取消收藏」
    expect(_toggleButton(tester, '添加收藏').enabled, isFalse);
    // 下载 / 复制链接 / 二维码都复用这份分享信息，等它回来再放开
    expect(_toggleButton(tester, '下载').enabled, isFalse);
    expect(_toggleButton(tester, '复制链接').enabled, isFalse);
    expect(_toggleButton(tester, '显示二维码').enabled, isFalse);
    // 更多菜单使用列表里的数据，不依赖这次分享请求。
    expect(_toggleButton(tester, '更多操作').enabled, isTrue);
  });

  testWidgets('文件属性弹窗：下载 / 复制链接 / 二维码复用弹窗取回的分享信息', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    // 打开弹窗时取过一次（收藏判定）
    expect(client.shareFileCalls, 1);

    // 弹菜单、选「复制分享链接」都不再请求分享信息
    await tester.tap(_sheetTooltip('复制链接'));
    await tester.pumpAndSettle();
    expect(client.shareFileCalls, 1);
    await tester.tap(find.text('复制分享链接'));
    await _settleSheet(tester);
    expect(client.shareFileCalls, 1);
    // 复制完属性弹窗还在（反馈走浮在最上层的轻提示）
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
  });

  testWidgets('文件属性弹窗：收藏就地切换，不关弹窗', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await tester.tap(find.byTooltip('添加收藏'));
    await _settleSheet(tester);

    // 测试环境没有 sqflite：收藏会失败并回滚，但弹窗必须还在
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    expect(_toggleButton(tester, '添加收藏').checked, isFalse);
  });

  testWidgets('网盘页文件夹 ⋯ 菜单：重命名与简介拆分，属性打开属性弹窗', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件夹操作'));
    // ⋯ 菜单是弹簧展开的：pump 到它长出来
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // 文件夹菜单：打开 / 属性 / 复制链接 / 访问密码 / 重命名 / 修改简介 / 删除
    //（「打开」排第一，与点文件夹卡片等效；文件夹没有「移动」）
    const order = ['打开', '属性', '复制链接', '访问密码', '重命名', '修改简介', '删除'];
    expect(find.byType(M3eMenuRow), findsNWidgets(order.length));
    final tops = [
      for (final label in order)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(M3eMenuRow),
                matching: find.text(label),
              ),
            )
            .dy,
    ];
    for (int i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '「${order[i]}」要排在「${order[i - 1]}」下面',
      );
    }

    // 点「属性」→ 打开文件夹属性弹窗
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('属性')),
    );
    await _settleSheet(tester);
    // 菜单 → 弹窗比原来多一次路由（先收菜单再开弹窗）：多给一帧，
    // 让弹窗里的分享信息和统计请求跑完。
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    for (final tooltip in ['复制链接', '显示二维码', '添加收藏', '添加到快速访问', '更多操作']) {
      expect(_toggleButton(tester, tooltip), isNotNull, reason: tooltip);
    }
    // 测试环境没有 sqflite：读不到「是否已固定」，固定按钮保持置灰
    // （真机上库可用，读回来即恢复可点）
    expect(_toggleButton(tester, '添加到快速访问').enabled, isFalse);

    // 文件夹没有时间行，只展示类型、大小、文件数和密码状态。
    expect(_sheetText('类型'), findsOneWidget);
    expect(_sheetText('文件夹'), findsOneWidget);
    expect(_sheetText('大小'), findsOneWidget);
    expect(_sheetText('2.0 MB'), findsOneWidget);
    expect(_sheetText('文件数'), findsOneWidget);
    expect(_sheetText('7'), findsOneWidget);
    expect(_sheetText('访问密码'), findsOneWidget);
    expect(_sheetText('已启用'), findsOneWidget);
    expect(_sheetText('时间'), findsNothing);

    // 低频操作收进更多菜单，不再直接铺在属性页里。
    expect(_sheetText('重命名'), findsNothing);
    expect(_sheetText('修改简介'), findsNothing);
    expect(_sheetText('打开'), findsNothing);
    // 名称与简介是两个独立入口，不再带合并操作的副标题
    expect(_sheetText('修改名称与简介'), findsNothing);
    // 「打开链接」入口已删
    expect(_sheetText('打开链接'), findsNothing);
    expect(_sheetText('删除'), findsNothing);

    await _openPropertyMore(tester);
    const moreOrder = ['访问密码', '重命名', '修改简介', '删除'];
    expect(find.byType(M3eMenuRow), findsNWidgets(moreOrder.length));
    for (final label in moreOrder) {
      expect(_menuRowText(label), findsOneWidget, reason: label);
    }
    expect(_menuRowText('属性'), findsNothing);
    expect(_menuRowText('打开'), findsNothing);
    expect(_menuRowText('复制链接'), findsNothing);
    expect(_menuRowText('移动'), findsNothing);

    // 取消删除时文件夹属性页继续保留；确认动作由删除流程自己处理。
    await tester.tap(_menuRowText('删除'));
    await _settleSheet(tester);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await _settleSheet(tester);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(client.deletedItems, isEmpty);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('重命名'));
    await _settleSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      '新文件夹',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await _settleSheet(tester);
    expect(client.renamedFolders, ['新文件夹']);
    expect(_sheetText('新文件夹'), findsOneWidget);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('修改简介'));
    await _settleSheet(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '文件夹简介',
    );
    await tester.enterText(find.byType(TextField), '新文件夹简介');
    await tester.tap(find.text('确定'));
    await _settleSheet(tester);
    expect(client.savedFolderDescs, ['新文件夹简介']);

    // 复制链接复用打开弹窗时取回的分享信息（不再请求一次）；
    // 注意这一步会把弹窗收起来，所以放在弹窗内容断言之后。
    expect(client.shareFolderCalls, 1);
    await tester.tap(_sheetTooltip('复制链接'));
    await _settleSheet(tester);
    expect(client.shareFolderCalls, 1);
  });

  testWidgets('文件属性弹窗：重命名与修改简介分别保存', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('重命名'));
    await _settleSheet(tester);

    // 只有名称输入框，预填当前名称
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('drive-rename-field')))
          .controller
          ?.text,
      'a.zip',
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      'b.zip',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await _settleSheet(tester);

    expect(client.renamedFiles, ['b.zip']);
    expect(client.savedDescs, isEmpty);
    expect(_sheetText('b.zip'), findsOneWidget);

    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('修改简介'));
    await _settleSheet(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '文件简介',
    );
    await tester.enterText(find.byType(TextField), '新简介');
    await tester.tap(find.text('确定'));
    await _settleSheet(tester);

    expect(client.savedDescs, ['新简介']);
    expect(_sheetText('b.zip'), findsOneWidget);

    // 让提示条走完（否则测试结束时还挂着它的定时器）
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('文件属性弹窗：非会员重命名失败提示跟随英文界面', (tester) async {
    final app = _FakeApp(_MemberRenameClient());
    const locale = Locale('en');
    final l10n = lookupAppLocalizations(locale);
    await _pumpDrive(tester, app, locale: locale, freeTier: true);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await _openPropertyMore(tester, label: l10n.moreActions);
    await tester.tap(_menuRowText(l10n.rename));
    await _settleSheet(tester);

    expect(
      find.byKey(const ValueKey('drive-rename-supporting-text')),
      findsOneWidget,
    );
    expect(find.text(l10n.fileRenameMembershipHint), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('drive-rename-field')),
    );
    expect(field.decoration?.helperText, isNull);
    await tester.enterText(find.byType(TextField).first, 'b.zip');
    await tester.tap(find.text(l10n.modify));
    await _settleSheet(tester);

    expect(find.text(l10n.lanzouRenameRequiresMembership), findsOneWidget);
    expect(find.text('重命名失败：此功能需要开通会员'), findsNothing);
  });

  testWidgets('文件属性弹窗：重命名名称为空时原地标错，弹窗不关也不发请求', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await _openPropertyMore(tester);
    await tester.tap(_menuRowText('重命名'));
    await _settleSheet(tester);

    // 清空名称后确定：MD3E error state（错误文本 + 尾部 fill 风格 Error 图标）
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('修改'));
    await _settleSheet(tester);
    expect(find.text('请输入名称'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    // 弹窗还在，重命名接口没有被调用
    expect(find.byType(TextField), findsOneWidget);
    expect(client.renamedFiles, isEmpty);
    expect(client.savedDescs, isEmpty);

    // 补上名字就能正常保存
    await tester.enterText(find.byType(TextField).first, 'b.zip');
    await tester.tap(find.text('修改'));
    await _settleSheet(tester);
    expect(client.renamedFiles, ['b.zip']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('文件夹属性弹窗：从网盘页「目录属性」进来不显示「打开」', (tester) async {
    final app = _FakeApp(_FakeClient());
    // 站在子目录里：顶栏菜单才会出现「目录属性」
    await _pumpDrive(tester, app, folderId: 'fd1', folderName: '子文件夹');

    await tester.tap(find.byTooltip('菜单'));
    await _settleSheet(tester);
    await tester.tap(find.text('目录属性'));
    await _settleSheet(tester);

    expect(_sheetTooltip('更多操作'), findsOneWidget);
    expect(_sheetText('重命名'), findsNothing);
    expect(_sheetText('修改简介'), findsNothing);
    expect(_sheetText('打开'), findsNothing);

    await _openPropertyMore(tester);
    expect(_menuRowText('打开'), findsNothing);
    expect(_menuRowText('属性'), findsNothing);
  });

  testWidgets('弹窗里的列表组：容器色比弹窗底高一档、窗体边距 16dp', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    void expectSheetList() {
      final list = tester.widget<SegmentedList>(
        find
            .descendant(
              of: find.byType(SheetListGroup),
              matching: find.byType(SegmentedList),
            )
            .first,
      );
      final scheme = Theme.of(tester.element(find.byType(SheetListGroup)))
          .colorScheme;
      // 比弹窗底（surfaceContainerLow）高一档
      expect(list.color, scheme.surfaceContainer);
      // 作为弹窗内容最后一块：底边与左右同值（16dp），是三边 16dp 的窗体边距
      expect(list.margin, SheetListGroup.endMargin);
    }

    // 文件属性弹窗
    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    expectSheetList();
    await tester.tapAt(const Offset(10, 10));
    await _settleSheet(tester);

    // 「添加」弹窗
    await tester.tap(find.text('添加'));
    await _settleSheet(tester);
    expectSheetList();
  });
}
