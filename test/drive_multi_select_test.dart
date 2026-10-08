import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网盘页挂载在目录缓存上（不进网络）：给个账号让 `app.client` 非空，
/// 再塞一份根目录快照，`_load()` 直接命中缓存。
Future<AppController> host(WidgetTester tester, {bool grid = true}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppController();
  app.accounts.accounts = [Account(uid: '1', cookie: 'cookie')];
  app.accounts.activeUid = '1';
  app.settings.gridView = grid;
  app.driveCache.put(
    '-1',
    CachedFolder(
      folders: [LzFolder(id: 'f1', name: '测试文件夹', desc: '')],
      files: [LzFile(id: 'l1', name: '测试文件.zip', size: '1M', time: '')],
      path: const [],
      page: 1,
      hasMore: false,
    ),
  );
  final manager = TransferManager(app);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<TransferManager>.value(value: manager),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const DrivePage(tabIndex: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 语义树里是否还有包含 [target] 的文字（label 或 tooltip）。
bool hasSemanticsLabel(WidgetTester tester, String target) {
  // ignore: deprecated_member_use
  final owner = tester.binding.pipelineOwner.semanticsOwner!;
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

void main() {
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
