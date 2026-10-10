import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

/// 固定返回一个文件 + 一个文件夹，并给出可预测的分享信息。
///
/// 收藏 / 快速访问的选中态要读本地库，测试环境里没有 sqflite 插件，
/// 这里只覆盖「结构」：一行 5 个图标按钮 + 底部低频列表；选中态本身由
/// test/m3e_icon_button_group_test.dart 与真机验证覆盖。
class _FakeClient extends LanzouClient {
  _FakeClient() : super(uid: '1');

  static const String fileUrl = 'https://share.example/file-f1';
  static const String folderUrl = 'https://share.example/folder-fd1';

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
              time: '',
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
  Future<ShareInfo> shareInfoOfFile(String fileId) async => ShareInfo(
    url: fileUrl,
    pwd: 'abcd',
    isFile: true,
    name: 'a.zip',
    desc: '文件简介',
  );

  @override
  Future<ShareInfo> shareInfoOfFolder(String folderId) async =>
      ShareInfo(url: folderUrl, pwd: 'efgh', isFile: false, name: '子文件夹');

  @override
  Future<({String size, int count, String name, String desc, String url})?>
  folderStats(String folderId) async => null;
}

class _FakeApp extends AppController {
  _FakeApp(this._client);

  final LanzouClient _client;

  @override
  LanzouClient get client => _client;
}

/// 分享信息卡住不返回的客户端：用来验「数据没回来时按钮置灰」。
class _GatedClient extends _FakeClient {
  final Completer<ShareInfo> share = Completer<ShareInfo>();

  @override
  Future<ShareInfo> shareInfoOfFile(String fileId) => share.future;
}

/// 弹窗里那一行图标按钮：按 tooltip 找到对应按钮。
M3EToggleButton _toggleButton(WidgetTester tester, String tooltip) => tester
    .widgetList<M3EToggleButton>(find.byType(M3EToggleButton))
    .firstWhere((button) => button.tooltip == tooltip);

/// 弹窗（面板）内的文字：页面本身也有「删除」等按钮，断言要限定在弹窗里。
Finder _sheetText(String text) =>
    find.descendant(of: find.byType(M3EBottomSheet), matching: find.text(text));

Future<void> _pumpDrive(WidgetTester tester, _FakeApp app) async {
  final manager = TransferManager(app);
  addTearDown(app.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<TransferManager>.value(value: manager),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const DrivePage(
          initialFolderId: '-1',
          initialName: '根目录',
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
  testWidgets('文件属性弹窗：常用操作收成一行图标按钮，列表只剩低频项', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);

    // 一行 5 个纯图标按钮：下载 / 复制链接 / 二维码 / 收藏 / 访问密码
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    for (final tooltip in ['下载', '复制链接', '显示二维码', '添加收藏', '访问密码']) {
      expect(_toggleButton(tester, tooltip), isNotNull, reason: tooltip);
    }
    // 提取码：文件本身带密码，按钮直接显示选中态
    expect(_toggleButton(tester, '访问密码').checked, isTrue);
    // 访问密码用锁图标
    expect(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );

    expect(_sheetText('修改简介'), findsOneWidget);
    expect(_sheetText('移动'), findsOneWidget);
    expect(_sheetText('打开链接'), findsOneWidget);
    expect(_sheetText('删除'), findsOneWidget);
    // 原来的「更多操作」入口被这行按钮组替代
    expect(_sheetText('更多操作'), findsNothing);
  });

  testWidgets('文件属性弹窗：复制链接弹出 MD3E 菜单（分享链接 / 下载直链）', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await tester.tap(find.byTooltip('复制链接'));
    await _settleSheet(tester);

    // 菜单是挂在按钮组上的弹出菜单：属性弹窗还在，菜单在它上面
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    expect(find.text('复制分享链接'), findsOneWidget);
    expect(find.text('复制下载直链'), findsOneWidget);
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
    // 其它不依赖这次请求的按钮照常可点
    expect(_toggleButton(tester, '下载').enabled, isTrue);
    expect(_toggleButton(tester, '复制链接').enabled, isTrue);
    expect(_toggleButton(tester, '显示二维码').enabled, isTrue);
    expect(_toggleButton(tester, '访问密码').enabled, isTrue);
  });

  testWidgets('文件夹属性弹窗：一行 5 个图标按钮 + 低频列表', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件夹操作'));
    await _settleSheet(tester);

    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    for (final tooltip in ['复制链接', '显示二维码', '添加收藏', '添加到快速访问', '访问密码']) {
      expect(_toggleButton(tester, tooltip), isNotNull, reason: tooltip);
    }
    expect(_toggleButton(tester, '访问密码').checked, isTrue);
    expect(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );
    // 测试环境没有 sqflite：读不到「是否已固定」，固定按钮保持置灰
    // （真机上库可用，读回来即恢复可点）
    expect(_toggleButton(tester, '添加到快速访问').enabled, isFalse);

    expect(_sheetText('修改信息'), findsOneWidget);
    expect(_sheetText('打开链接'), findsOneWidget);
    expect(_sheetText('删除'), findsOneWidget);
    // 文件夹没有「移动」
    expect(_sheetText('移动'), findsNothing);
  });
}
