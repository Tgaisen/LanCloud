import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 网盘页挂载在目录缓存上（不进网络）：给个账号让 `app.client` 非空，
/// 再塞一份根目录快照，`_load()` 直接命中缓存。
Future<AppController> host(
  WidgetTester tester, {
  bool grid = true,
  List<LzFile>? files,
}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppController();
  app.accounts.accounts = [Account(uid: '1', cookie: 'cookie')];
  app.accounts.activeUid = '1';
  app.settings.gridView = grid;
  app.driveCache.put(
    '-1',
    CachedFolder(
      folders: [LzFolder(id: 'f1', name: '测试文件夹', desc: '')],
      files:
          files ?? [LzFile(id: 'l1', name: '测试文件.zip', size: '1M', time: '')],
      path: const [],
      page: 1,
      hasMore: false,
    ),
  );
  final manager = TransferManager(app);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [transferManagerProvider.overrideWithValue(manager)],
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: app),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const DrivePage(tabIndex: 0),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 语义树里是否还有包含 [target] 的文字（label 或 tooltip）。
bool hasSemanticsLabel(WidgetTester tester, String target) {
  // 语义树挂在 RenderView 的 PipelineOwner 上（binding.pipelineOwner 已弃用）。
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  var found = false;
  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label.contains(target) || data.tooltip.contains(target)) {
      found = true;
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  return found;
}

/// 语义树里所有包含 [label] 的节点数据（诊断选中态挂在哪颗节点上）。
List<SemanticsData> semanticsDataWith(WidgetTester tester, String label) {
  final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
  final out = <SemanticsData>[];
  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label.contains(label)) out.add(data);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(owner.rootSemanticsNode!);
  return out;
}

void main() {
  // 鼠标：点图标块 = 进入多选并选中，不应打开文件夹；已选中时再点 = 取消选中。
  testWidgets('鼠标：点图标块进入多选并选中，再点取消选中', (tester) async {
    // 运行时检测到鼠标才启用（见 MousePresenceDetector），测试里直接置真
    PointerSupport.hasMouse.value = true;
    try {
      for (final grid in [true, false]) {
        // 先清空树：否则同一位置会复用上一轮的 DrivePage State（还在多选态）
        await tester.pumpWidget(const SizedBox.shrink());
        final app = await host(tester, grid: grid);
        expect(find.text('根目录'), findsOneWidget);
        await tester.tap(find.byIcon(app_icons.Icons.folder).first);
        await tester.pumpAndSettle();

        expect(find.text('已选择 1 项'), findsOneWidget, reason: '$grid');
        // 还停在根目录（点图标没有触发「打开文件夹」）
        expect(find.text('根目录'), findsOneWidget, reason: '$grid');

        // 已选中：再点同一个图标块 → 取消选中，并自动退出多选
        await tester.tap(find.byIcon(app_icons.Icons.check_circle).first);
        await tester.pumpAndSettle();
        expect(find.text('已选择 1 项'), findsNothing, reason: '$grid');
        // 没有停在「已选择 0 项」：多选整体退出，图标也恢复成文件夹
        expect(app.selectionMode, isFalse, reason: '$grid');
        expect(
          find.byIcon(app_icons.Icons.check_circle),
          findsNothing,
          reason: '$grid',
        );
        expect(find.text('根目录'), findsOneWidget, reason: '$grid');
      }
    } finally {
      PointerSupport.hasMouse.value = false;
    }
  });

  // 读屏（TalkBack）聚焦结构：卡片本体要自带名字和「点击进入」的动作，
  // 「文件夹操作 / 文件操作」必须是它下面独立的一颗节点（向右滑一层才到）。
  // 曾经的写法把 Semantics(selected:) 包进 InkWell 里面，整张卡片的文字
  // 会并进 ⋯ 那颗节点（读成「文件操作、测试文件夹…」），卡片本体反而成了
  // 没有 label 的节点，读屏就进不去文件夹 / 文件了。
  testWidgets('网格卡片：本体带名字与点击动作，⋯ 是独立节点', (tester) async {
    final handle = tester.ensureSemantics();
    await host(tester, grid: true);

    for (final (name, menuLabel) in [
      ('测试文件夹', '文件夹操作'),
      ('测试文件.zip', '文件操作'),
    ]) {
      final datas = semanticsDataWith(tester, name);
      // 本体：label 第一行就是名字（没有被 ⋯ 的 tooltip 拼进来），可点、可长按
      final body = datas
          .where((d) => d.label.split('\n').first == name)
          .toList();
      expect(body, hasLength(1), reason: name);
      expect(body.single.hasAction(SemanticsAction.tap), isTrue, reason: name);
      expect(
        body.single.hasAction(SemanticsAction.longPress),
        isTrue,
        reason: name,
      );
      // 没有任何节点把 tooltip 和名字拼在一起读
      expect(
        datas.any((d) => d.label.contains('操作') && d.label.contains(name)),
        isFalse,
        reason: name,
      );

      // ⋯ 独立成节点：在卡片里面，且明显比卡片小
      final menu = semanticsDataWith(tester, menuLabel).single;
      expect(menu.label, menuLabel);
      expect(menu.hasAction(SemanticsAction.tap), isTrue);
      expect(menu.rect.width, lessThan(body.single.rect.width));
    }

    // 选中后：本体节点自己带「已选中」（不是另起一颗没 label 的节点）
    await tester.longPress(find.text('测试文件夹'));
    await tester.pumpAndSettle();
    final selectedBody = semanticsDataWith(
      tester,
      '测试文件夹',
    ).where((d) => d.label.split('\n').first == '测试文件夹').toList();
    expect(selectedBody, hasLength(1));
    expect(selectedBody.single.flagsCollection.isSelected.name, 'isTrue');
    expect(selectedBody.single.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  // TalkBack：网格视图下多选也要读出「已选中」（列表视图一直正常）。
  testWidgets('多选选中态：网格与列表视图都要告诉读屏', (tester) async {
    final handle = tester.ensureSemantics();
    for (final grid in [false, true]) {
      await host(tester, grid: grid);
      await tester.longPress(find.text('测试文件夹'));
      await tester.pumpAndSettle();
      final datas = semanticsDataWith(tester, '测试文件夹');
      expect(
        datas.any((d) => d.flagsCollection.isSelected.name == 'isTrue'),
        isTrue,
        reason: grid ? '网格视图' : '列表视图',
      );
    }
    handle.dispose();
  });

  // 网格视图的卡片高度是固定的：长文件名（两行）+ 访问密码时，密码图标和大小
  // 必须同处一行，否则两行分开写会把大小挤到卡片边缘（甚至溢出）
  testWidgets('网格视图：长文件名 + 访问密码时，密码图标与大小同一行', (tester) async {
    await host(
      tester,
      files: [
        LzFile(
          id: 'l1',
          name: '蓝云_26.1.0-snapshot.1.apk',
          size: '22.6M',
          time: '',
          hasPwd: true,
        ),
      ],
    );

    // 长名字要真的占满两行，才谈得上「挤」
    expect(
      tester.getSize(find.text('蓝云_26.1.0-snapshot.1.apk')).height,
      greaterThan(30),
    );

    final lock = find.byIcon(app_icons.Icons.lock_outline);
    expect(lock, findsOneWidget);
    // 图标跟着 bodySmall 的字号走
    expect(tester.widget<Icon>(lock).size, 12);
    // 和大小文本同一行：中心线对齐
    expect(
      (tester.getCenter(lock).dy - tester.getCenter(find.text('22.6 MB')).dy)
          .abs(),
      lessThan(2),
    );
  });

  // 网盘页搜索：关闭按钮改到左侧（与收藏页一致）
  testWidgets('网盘页搜索：关闭按钮在左侧，右侧不再有搜索按钮', (tester) async {
    final app = await host(tester);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    final close = find.byTooltip('关闭搜索');
    expect(close, findsOneWidget);
    expect(find.byTooltip('搜索'), findsNothing);
    // 位于搜索框左侧
    expect(
      tester.getCenter(close).dx,
      lessThan(tester.getTopLeft(find.byType(TextField)).dx),
    );

    app.dispose();
  });

  // 多选时行尾 ⋯ 菜单没有意义（操作都在底部多选条里），和收藏 / 传输页
  // 一样把它藏起来；但只是「看不见」而不是「不占位」，否则条目高度会跳。
  testWidgets('网盘页进入多选隐藏 ⋯ 但保留占位：高度不变、读屏读不到', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await host(tester);

    final folderItem = find.byKey(const ValueKey('-1-f-f1'));
    final fileItem = find.byKey(const ValueKey('-1-l-l1'));
    final folderHeight = tester.getSize(folderItem).height;
    final fileHeight = tester.getSize(fileItem).height;
    expect(find.text('测试文件夹'), findsOneWidget);
    expect(find.byTooltip('文件夹操作'), findsOneWidget);
    expect(find.byTooltip('文件操作'), findsOneWidget);
    expect(hasSemanticsLabel(tester, '文件夹操作'), isTrue);
    expect(hasSemanticsLabel(tester, '文件操作'), isTrue);

    await tester.longPress(find.text('测试文件夹'));
    await tester.pumpAndSettle();
    expect(app.selectionMode, isTrue);
    // 占位保留：条目高度一点都不能变
    expect(tester.getSize(folderItem).height, folderHeight);
    expect(tester.getSize(fileItem).height, fileHeight);
    // 隐藏的 ⋯ 仍在树里（占位），但读屏语义里没有了
    expect(hasSemanticsLabel(tester, '文件夹操作'), isFalse);
    expect(hasSemanticsLabel(tester, '文件操作'), isFalse);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(app.selectionMode, isFalse);
    expect(tester.getSize(folderItem).height, folderHeight);
    expect(tester.getSize(fileItem).height, fileHeight);
    expect(find.byTooltip('文件夹操作'), findsOneWidget);
    expect(find.byTooltip('文件操作'), findsOneWidget);
    expect(hasSemanticsLabel(tester, '文件夹操作'), isTrue);
    expect(hasSemanticsLabel(tester, '文件操作'), isTrue);

    handle.dispose();
    app.dispose();
  });

  // 列表形态（设置里的「列表」视图）同样要保占位：走的是 _DriveRow。
  testWidgets('网盘列表视图进入多选也保留 ⋯ 占位', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await host(tester, grid: false);

    final folderItem = find.byKey(const ValueKey('-1-f-f1'));
    final fileItem = find.byKey(const ValueKey('-1-l-l1'));
    final folderHeight = tester.getSize(folderItem).height;
    final fileHeight = tester.getSize(fileItem).height;
    expect(hasSemanticsLabel(tester, '文件夹操作'), isTrue);

    await tester.longPress(find.text('测试文件.zip'));
    await tester.pumpAndSettle();
    expect(app.selectionMode, isTrue);
    expect(tester.getSize(folderItem).height, folderHeight);
    expect(tester.getSize(fileItem).height, fileHeight);
    expect(hasSemanticsLabel(tester, '文件夹操作'), isFalse);
    expect(hasSemanticsLabel(tester, '文件操作'), isFalse);

    // 先退出多选再收尾：页面 dispose 时不能去动已销毁的控制器
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    handle.dispose();
    app.dispose();
  });
}
