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
import 'package:lancloud/ui/legal_dialog.dart';
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

  /// 分享信息请求次数：用来验「属性弹窗取过一次后，下载 / 复制链接 /
  /// 二维码复用这份，不再各请求一次」。
  int shareFileCalls = 0;
  int shareFolderCalls = 0;

  /// 「修改信息」流程里实际调用的接口参数。
  final List<String> renamedFiles = <String>[];
  final List<String> savedDescs = <String>[];

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
  Future<void> setFileName(String fileId, String name) async =>
      renamedFiles.add(name);

  @override
  Future<void> setDesc(String fileId, String desc) async =>
      savedDescs.add(desc);

  @override
  Future<ShareInfo> shareInfoOfFile(String fileId) async {
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
    return ShareInfo(url: folderUrl, pwd: 'efgh', isFile: false, name: '子文件夹');
  }

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

Future<void> _pumpDrive(
  WidgetTester tester,
  _FakeApp app, {
  String folderId = '-1',
  String folderName = '根目录',
  VisualDensity density = VisualDensity.standard,
  Size viewSize = const Size(420, 900),
}) async {
  final manager = TransferManager(app);
  addTearDown(app.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewSize;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<TransferManager>.value(value: manager),
      ],
      child: MaterialApp(
        theme: ThemeData(visualDensity: density),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
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
  testWidgets('网盘页文件 ⋯ 菜单：五项操作，属性打开属性弹窗', (tester) async {
    final app = _FakeApp(_FakeClient());
    await _pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件操作'));
    // ⋯ 菜单是弹簧展开的：pump 到它长出来（真机一两帧，测试里有界多给点）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(M3eMenuRow), findsNWidgets(5));
    const order = ['属性', '访问密码', '修改信息', '移动', '删除'];
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
    // 顺序：属性 / 访问密码 / 修改信息 / 移动 / 删除
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
    // 原来那套「更多操作」弹窗（含修改简介）已经不在
    expect(find.text('修改简介'), findsNothing);

    // 点「属性」→ 打开文件属性弹窗（那一行 5 个图标按钮）
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('属性')),
    );
    await _settleSheet(tester);
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    expect(_sheetText('修改信息'), findsOneWidget);
  });

  testWidgets('宽屏：新建文件夹弹窗宽度固定，不超过 M3 上限 560', (tester) async {
    final app = _FakeApp(_FakeClient());
    // 宽屏（横屏 / 桌面）：以前弹窗会跟着输入内容一路变宽
    await _pumpDrive(tester, app, viewSize: const Size(1200, 700));

    await tester.tap(find.text('添加'));
    await _settleSheet(tester);
    await tester.tap(find.text('新建文件夹'));
    await _settleSheet(tester);

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

  testWidgets('桌面端紧凑密度：菜单放得下时卡片贴着内容，底部不多留白', (tester) async {
    final app = _FakeApp(_FakeClient());
    // Windows 桌面默认 visualDensity.compact：行高被压到 40dp 而不是 48dp。
    // 卡片高度如果按 48dp 硬算，完全展开时底部就会多出一截空白。
    await _pumpDrive(tester, app, density: VisualDensity.compact);

    await tester.tap(find.byTooltip('文件操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    final rows = find.byType(M3eMenuRow);
    expect(rows, findsNWidgets(5));
    // 卡片 = 菜单行最近的 Material 祖先
    final Rect card = tester.getRect(
      find.ancestor(of: rows.first, matching: find.byType(Material)).first,
    );
    final Rect first = tester.getRect(rows.first);
    final Rect last = tester.getRect(rows.last);
    expect(first.height, 40, reason: '紧凑密度下 MenuItemButton 行高 40dp');
    expect(first.top - card.top, 4, reason: '首项到卡片顶边也是 4dp');
    expect(card.bottom - last.bottom, 4, reason: '末项到卡片底边也是 4dp');
  });

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

    expect(_sheetText('修改信息'), findsOneWidget);
    expect(_sheetText('移动'), findsOneWidget);
    expect(_sheetText('删除'), findsOneWidget);
    // 「打开链接」入口已删（提示条里的复制链接等照旧）
    expect(_sheetText('打开链接'), findsNothing);
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
    // 菜单是弹簧展开的：等它长出来再断言（真机上就是一两帧的事）
    await tester.pumpAndSettle();

    // 菜单是贴在被点那一段下面的弹出菜单：属性弹窗还在，菜单浮在它上面
    expect(find.byType(M3EToggleButton), findsNWidgets(5));
    expect(find.byType(M3eMenuRow), findsNWidgets(2));
    expect(find.text('复制分享链接'), findsOneWidget);
    expect(find.text('复制下载直链'), findsOneWidget);

    // 菜单左缘跟着被点的那一段（而不是整个按钮组），并且贴着它的下边缘
    final Rect button = tester.getRect(find.byTooltip('复制链接'));
    final Rect item = tester.getRect(find.byType(M3eMenuRow).first);
    expect(
      (item.left - button.left).abs(),
      lessThan(24),
      reason: '菜单左缘要对准被点的那一段',
    );
    expect(item.top, greaterThan(button.bottom), reason: '菜单要贴在那一段下方');
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
    // 访问密码用列表里的数据 / 自己的弹窗，不依赖这次请求
    expect(_toggleButton(tester, '访问密码').enabled, isTrue);
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
    await tester.tap(find.byTooltip('复制链接'));
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

  testWidgets('文件夹属性弹窗：一行 5 个图标按钮 + 低频列表', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
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

    // 「打开」在「修改信息」上方（从列表里某个文件夹的三点菜单进来）
    expect(_sheetText('打开'), findsOneWidget);
    expect(_sheetText('修改信息'), findsOneWidget);
    expect(
      tester.getTopLeft(_sheetText('打开')).dy,
      lessThan(tester.getTopLeft(_sheetText('修改信息')).dy),
    );
    // 修改信息不再带副标题
    expect(_sheetText('修改名称与简介'), findsNothing);
    // 「打开链接」入口已删
    expect(_sheetText('打开链接'), findsNothing);
    expect(_sheetText('删除'), findsOneWidget);
    // 文件夹没有「移动」
    expect(_sheetText('移动'), findsNothing);

    // 复制链接复用打开弹窗时取回的分享信息（不再请求一次）；
    // 注意这一步会把弹窗收起来，所以放在弹窗内容断言之后。
    expect(client.shareFolderCalls, 1);
    await tester.tap(find.byTooltip('复制链接'));
    await _settleSheet(tester);
    expect(client.shareFolderCalls, 1);
  });

  testWidgets('文件属性弹窗：修改信息能改名称与简介', (tester) async {
    final client = _FakeClient();
    final app = _FakeApp(client);
    await _pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await _settleSheet(tester);
    await tester.tap(_sheetText('修改信息'));
    await _settleSheet(tester);

    // 名称 + 简介两个输入框，预填当前值
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).first, 'b.zip');
    await tester.enterText(find.byType(TextField).last, '新简介');
    await tester.tap(find.text('确定'));
    await _settleSheet(tester);

    // 改名 + 简介都落到接口上，弹窗标题跟着更新
    expect(client.renamedFiles, ['b.zip']);
    expect(client.savedDescs, ['新简介']);
    expect(_sheetText('b.zip'), findsOneWidget);

    // 让「信息已更新」提示条走完（否则测试结束时还挂着它的定时器）
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

    expect(_sheetText('修改信息'), findsOneWidget);
    expect(_sheetText('打开'), findsNothing);
  });
}
