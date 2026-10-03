import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:provider/provider.dart';

TransferTask task(
  String id,
  String name, {
  required TransferStatus status,
}) {
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
    find.ancestor(
      of: find.text('重试'),
      matching: find.byType(BatchAction),
    ),
  );
  return action.onPressed != null;
}

void main() {
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
    expect(find.byKey(const ValueKey('transfers-selection-appbar')), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(manager.tasks.map((t) => t.id).toList(), ['t2']);
    expect(app.selectionMode, isFalse);
    app.dispose();
  });

  testWidgets('独立页面打开时不再保留底栏专用的尾部留白（96）', (tester) async {
    final app = AppController();
    final manager = TransferManager(app);
    manager.tasks.addAll([
      for (var i = 0; i < 12; i++)
        task('t$i', 'file$i.zip', status: TransferStatus.done),
    ]);

    Widget host(Widget home, {GlobalKey<NavigatorState>? navKey}) => MultiProvider(
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

    // 作为外壳里的底栏项目：末尾保留给悬浮 / 收起底栏让位的 96
    await tester.pumpWidget(host(const TransfersPage()));
    await tester.pumpAndSettle();
    final inShellGap = await tailGap();

    // 作为独立页面（push）：末尾只留系统导航栏 + 常规留白，不再叠加 96
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(host(const Scaffold(), navKey: navKey));
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const TransfersPage()),
    );
    await tester.pumpAndSettle();
    final pushedGap = await tailGap();

    expect(inShellGap - pushedGap, 96);
    app.dispose();
  });
}
