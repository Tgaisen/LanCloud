import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:provider/provider.dart';

TransferTask task(String id, String name, {required TransferStatus status}) {
  return TransferTask(
    id: id,
    kind: TransferKind.upload,
    name: name,
    accountUid: '',
    localFilePath: '/tmp/$name',
  )..status = status;
}

Future<(AppController, TransferManager)> host(WidgetTester tester) async {
  final app = AppController();
  final manager = TransferManager(app);
  manager.tasks.addAll([
    task('t1', 'a.zip', status: TransferStatus.failed),
    task('t2', 'b.zip', status: TransferStatus.failed),
    task('t3', 'c.zip', status: TransferStatus.done),
  ]);
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
        home: const TransfersPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (app, manager);
}

bool retryEnabled(WidgetTester tester) {
  final action = tester.widget<BatchAction>(
    find.ancestor(of: find.text('重试'), matching: find.byType(BatchAction)),
  );
  return action.onPressed != null;
}

/// 把传输页作为独立页面（二级路由）打开，用于验证返回行为。
Future<AppController> pushTransfers(WidgetTester tester) async {
  final app = AppController();
  final manager = TransferManager(app);
  manager.tasks.addAll([task('t1', 'a.zip', status: TransferStatus.failed)]);
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    // 独立打开时外壳传的就是同一个 tabIndex（见 app.dart
                    // 的 _openView），这里保持一致，避免判断错页面形态
                    builder: (_) => const TransfersPage(tabIndex: 2),
                  ),
                ),
                child: const Text('打开传输'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开传输'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('进行中条目的进度条与标题同宽：避让左侧图标与右侧按钮', (tester) async {
    final app = AppController();
    final manager = TransferManager(app);
    manager.tasks.add(
      task('t1', 'a.zip', status: TransferStatus.running)
        ..received = 1
        ..total = 2,
    );
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
          home: const TransfersPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('a.zip'));
    final bar = tester.getRect(find.byType(LinearProgressIndicator));
    final cancel = tester.getRect(find.byTooltip('取消'));
    // 左边缘与标题对齐（在文字列里，自然避让 42dp 图标与 14dp 间距）
    expect(bar.left, closeTo(title.left, 0.5));
    // 右边缘不越过右侧按钮
    expect(bar.right, lessThanOrEqualTo(cancel.left));
    expect(bar.width, greaterThan(0));
  });

  testWidgets('独立页面：多选时返回只退出多选，不退出页面', (tester) async {
    final app = await pushTransfers(tester);

    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(app.selectionMode, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.selectionMode, isFalse);
    expect(find.byType(TransfersPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TransfersPage), findsNothing);
  });

  testWidgets('直接点击条目进入多选并选中它（多选栏一起出现）', (tester) async {
    final (app, _) = await host(tester);

    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('transfers-selection-appbar')),
      findsOneWidget,
    );
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(app.selectionMode, isTrue);
  });

  testWidgets('长按进入多选：显示已选数量，重试仅对失败项可用', (tester) async {
    final (app, manager) = await host(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfers-selection-appbar')),
      findsOneWidget,
    );
    expect(find.text('已选择 1 项'), findsOneWidget);
    // 选中的是失败项 → 重试可用
    expect(retryEnabled(tester), isTrue);

    // 再加选一个已完成项，计数更新
    await tester.tap(find.text('c.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(retryEnabled(tester), isTrue);

    // 只选已完成项时重试不可用
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(retryEnabled(tester), isFalse);

    // 退出多选
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(app.selectionMode, isFalse);
    expect(manager.tasks.length, 3);
    app.dispose();
  });

  testWidgets('多选删除：确认后移除选中记录', (tester) async {
    final (app, manager) = await host(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('c.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 确认弹窗
    expect(find.text('删除传输记录'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    // 批量删除不逐条播删除动画：确认后立即移除记录，不需要等动画
    await tester.pump();
    await tester.pump();
    expect(manager.tasks.map((t) => t.id).toList(), ['t2']);
    await tester.pumpAndSettle();

    expect(manager.tasks.map((t) => t.id).toList(), ['t2']);
    // 列表一次刷新到位：被删的两条都不再渲染
    expect(find.text('a.zip'), findsNothing);
    expect(find.text('c.zip'), findsNothing);
    expect(find.text('b.zip'), findsOneWidget);
    expect(app.selectionMode, isFalse);
    app.dispose();
  });

  testWidgets('下载完成的项目：APK 只保留「打开」，不再显示「安装」', (tester) async {
    final app = AppController();
    final manager = TransferManager(app);
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'tool.apk',
          accountUid: '',
        )
        ..status = TransferStatus.done
        ..savedPath = '/tmp/tool.apk',
    );
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
          home: const TransfersPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(find.text('tool.apk'), findsOneWidget);
    expect(find.byTooltip('安装'), findsNothing);
    expect(find.byTooltip('打开'), findsOneWidget);
    app.dispose();
  });

  testWidgets('批量删除：幸存条目复用元素，不重播出现动画', (tester) async {
    final app = AppController();
    final manager = TransferManager(app);
    for (var i = 1; i <= 5; i++) {
      manager.tasks.add(
        TransferTask(
            id: 'd$i',
            kind: TransferKind.download,
            name: 'f$i.zip',
            accountUid: '',
          )
          ..status = TransferStatus.done
          ..savedPath = '/tmp/f$i.zip',
      );
    }
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
          home: const TransfersPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    // 下载列表按时间倒序：f5 f4 f3 f2 f1；删掉 f4、f2，剩下 f5 f3 f1
    await tester.longPress(find.text('f4.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('f2.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('f4.zip'), findsNothing);
    expect(find.text('f2.zip'), findsNothing);
    expect(manager.tasks.length, 3);
    // 下标变了（f3: 2→1、f1: 4→2）但元素复用，不会淡入一次
    for (final id in ['d3', 'd1', 'd5']) {
      final opacity = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byKey(ValueKey('transfer-$id')),
              matching: find.byType(Opacity),
            ),
          )
          .map((o) => o.opacity)
          .reduce((a, b) => a < b ? a : b);
      expect(opacity, 1.0);
    }
    await tester.pumpAndSettle();
    app.dispose();
  });

  testWidgets('独立页面与外壳里的尾部留白一致（都由 shellBottomBarInset 决定）', (tester) async {
    // 这条用例量的是单列列表的末尾留白：固定 Compact 窗口（<600dp），避免多列改变布局
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 600);
    addTearDown(tester.view.reset);
    final app = AppController();
    final manager = TransferManager(app);
    manager.tasks.addAll([
      for (var i = 0; i < 12; i++)
        task('t$i', 'file$i.zip', status: TransferStatus.done),
    ]);

    Widget host(Widget home, {GlobalKey<NavigatorState>? navKey}) =>
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppController>.value(value: app),
            ChangeNotifierProvider<TransferManager>.value(value: manager),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: home,
          ),
        );

    // 列表自己的滚动位置（不要用 Scrollable.last：页面里可能还有别的可滚动组件）
    ScrollPosition listPosition() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    /// 滚到底后，最后一条内容距列表底边的距离（= 末尾实际留白）
    Future<double> tailGap() async {
      listPosition().jumpTo(listPosition().maxScrollExtent);
      await tester.pumpAndSettle();
      return tester.getRect(find.byType(CustomScrollView)).bottom -
          tester.getRect(find.text('file0.zip')).bottom;
    }

    // 作为外壳里的底栏项目
    await tester.pumpWidget(host(const TransfersPage()));
    await tester.pumpAndSettle();
    final inShellGap = await tailGap();

    // 作为独立页面（push）
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(host(const Scaffold(), navKey: navKey));
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const TransfersPage()),
    );
    await tester.pumpAndSettle();
    final pushedGap = await tailGap();

    // 两者的底栏让位都由 shellBottomBarInset 统一给出（测试环境没有系统
    // 导航栏 inset），因此只剩页面自己的常规留白，两处应完全一致
    expect(inShellGap, closeTo(pushedGap, 0.5));
    app.dispose();
  });

  testWidgets('滑动时懒加载出来的条目不重播入场动画（与收藏页一致）', (tester) async {
    final app = AppController();
    final manager = TransferManager(app);
    for (var i = 0; i < 40; i++) {
      manager.tasks.add(task('t$i', 'file$i.zip', status: TransferStatus.done));
    }
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
          home: const TransfersPage(),
        ),
      ),
    );
    // 等首次入场动画播完（共享进度到 1）
    await tester.pumpAndSettle();

    // 滑到列表后段：这些条目是懒构建出来的
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2500));
    await tester.pumpAndSettle();

    // 新构建出来的条目直接显示，不重播动画
    final items = tester.widgetList<Md3ListItem>(find.byType(Md3ListItem));
    expect(items, isNotEmpty);
    for (final item in items) {
      final opacity = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byKey(item.key!),
              matching: find.byType(Opacity),
            ),
          )
          .map((o) => o.opacity)
          .reduce((a, b) => a < b ? a : b);
      expect(opacity, 1.0, reason: '${item.key} 不应重播入场动画');
    }
    app.dispose();
  });
}
