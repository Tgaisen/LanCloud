import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/transfers_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/transfer_page_test_support.dart';

void main() {
  testWidgets('批量删除：幸存条目复用元素，不重播出现动画', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
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
      transferTestHost(
        app: app,
        manager: manager,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const TransfersPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 同上：按钮组有离屏测量副本，取可点击的那份。
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();

    // 下载列表按时间倒序：f5 f4 f3 f2 f1；删掉 f4、f2，剩下 f5 f3 f1
    await tester.longPress(find.text('f4.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('f2.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
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
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.addAll([
      for (var i = 0; i < 12; i++)
        TransferTask(
          id: 't$i',
          kind: TransferKind.download,
          name: 'file$i.zip',
          accountUid: '',
        )..status = TransferStatus.done,
    ]);

    Widget host(Widget home, {GlobalKey<NavigatorState>? navKey}) =>
        transferTestHost(
          app: app,
          manager: manager,
          child: MaterialApp(
            navigatorKey: navKey,
            localizationsDelegates: appLocalizationsDelegates,
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
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    for (var i = 0; i < 40; i++) {
      manager.tasks.add(task('t$i', 'file$i.zip', status: TransferStatus.done));
    }
    await tester.pumpWidget(
      transferTestHost(
        app: app,
        manager: manager,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const TransfersPage(),
        ),
      ),
    );
    // 等首次入场动画播完（共享进度到 1）
    await tester.tap(find.text('上传').hitTestable());
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

  // 大屏（宽度 ≥ 640dp，底栏变侧栏）时多选条要和网盘页同色（surfaceContainer）；
  // 小屏维持 surface。AppBar 自己必须透明，否则它会把外层 Material 的颜色盖住。
  testWidgets('多选条底色：大屏用 surfaceContainer、小屏用 surface', (tester) async {
    Future<(AppEnvironment, Color?, Color?)> pumpAt(Size size) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      final (app, _) = await host(tester);
      await tester.longPress(find.text('a.zip'));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('transfers-selection-appbar')),
              matching: find.byType(Material),
            )
            .first,
      );
      final scheme = Theme.of(
        tester.element(
          find.byKey(const ValueKey('transfers-selection-appbar')),
        ),
      ).colorScheme;
      // 退出多选再收尾：页面 dispose 时会去改控制器，不能等到控制器释放之后
      await tester.tap(find.byTooltip('退出多选'));
      await tester.pumpAndSettle();
      return (app, material.color, scheme.surfaceContainer);
    }

    addTearDown(tester.view.reset);

    // 大屏：外层底色 = surfaceContainer，AppBar 透明（不盖色）
    final (bigApp, bigColor, bigSurfaceContainer) = await pumpAt(
      const Size(1200, 800),
    );
    expect(bigColor, bigSurfaceContainer);
    expect(
      tester
          .widget<AppBar>(
            find.byKey(const ValueKey('transfers-selection-appbar')),
          )
          .backgroundColor,
      Colors.transparent,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    bigApp.dispose();

    // 小屏：维持原来的 surface
    final (smallApp, smallColor, _) = await pumpAt(const Size(420, 900));
    expect(
      smallColor,
      Theme.of(
        tester.element(
          find.byKey(const ValueKey('transfers-selection-appbar')),
        ),
      ).colorScheme.surface,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    smallApp.dispose();
  });

  testWidgets('待开始上传单独分栏，行内提供上传按钮与目录/重命名/取消菜单', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task('u1', 'waiting.txt', status: TransferStatus.pending)..total = 12,
    ]);

    expect(find.text('待开始'), findsWidgets);
    expect(find.textContaining('12 B'), findsOneWidget);
    final uploadButton = find.byKey(const ValueKey('upload-start-u1'));
    expect(uploadButton, findsOneWidget);
    expect(
      find.descendant(
        of: uploadButton,
        matching: find.byIcon(app_icons.Icons.upload),
      ),
      findsOneWidget,
    );

    await openTransferRowMenu(tester, 'waiting.txt');
    expect(transferMenuLabels(tester), ['重命名', '修改上传目录', '取消上传']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('m3e-menu-card')),
        matching: find.byIcon(app_icons.Icons.drive_file_move_outline),
      ),
      findsOneWidget,
    );
    await tester.tap(transferMenuItem('取消上传'));
    await tester.pump();
    await tester.pump();
    expect(manager.tasks.map((task) => task.id), contains('u1'));
    expect(
      tester
          .widget<Md3ListItem>(
            find.ancestor(
              of: find.text('waiting.txt'),
              matching: find.byType(Md3ListItem),
            ),
          )
          .removing,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(manager.tasks, isEmpty);
    app.dispose();
  });

  testWidgets('清空待开始只移除待开始任务，不影响被跳过记录', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task('u1', 'pending.txt', status: TransferStatus.pending),
      task('u2', 'skipped.txt', status: TransferStatus.skipped),
    ]);

    await tester.tap(find.byKey(const ValueKey('transfers-clear-pending')));
    await tester.pumpAndSettle();
    expect(find.text('清空待开始上传'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transfer-delete-confirm')));
    await tester.pumpAndSettle();

    expect(manager.tasks.map((task) => task.id), ['u2']);
    expect(find.text('pending.txt'), findsNothing);
    expect(find.text('skipped.txt'), findsOneWidget);
    app.dispose();
  });

  testWidgets('待开始分栏按钮可一次启动全部待开始任务', (tester) async {
    final pendingOne =
        TransferTask(
            id: 'u1',
            kind: TransferKind.upload,
            name: 'one.txt',
            accountUid: '',
            streamFactory: () => Stream<List<int>>.value(const <int>[1]),
            sourceSize: 1,
          )
          ..status = TransferStatus.pending
          ..total = 1;
    final pendingTwo =
        TransferTask(
            id: 'u2',
            kind: TransferKind.upload,
            name: 'two.txt',
            accountUid: '',
            streamFactory: () => Stream<List<int>>.value(const <int>[1]),
            sourceSize: 1,
          )
          ..status = TransferStatus.pending
          ..total = 1;
    final (app, _) = await hostWithTasks(tester, [pendingOne, pendingTwo]);
    app.settingsState.store.maxUploads = 0;
    app.accountState.store.accounts.add(
      Account(uid: 'u1', cookie: 'phpdisk_info=x'),
    );
    app.accountState.store.activeUid = 'u1';

    await tester.tap(find.byKey(const ValueKey('transfers-upload-pending')));
    await tester.pumpAndSettle();

    expect(pendingOne.status, TransferStatus.queued);
    expect(pendingTwo.status, TransferStatus.queued);
    app.dispose();
  });

  testWidgets('上传多选栏为上传/改名/目录/删除/重试，下载多选栏为分享/删除/重试', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      task('u1', 'waiting.txt', status: TransferStatus.pending),
      task(
        'd1',
        'download.zip',
        status: TransferStatus.done,
        kind: TransferKind.download,
      )..savedPath = '/tmp/download.zip',
    ]);

    await tester.longPress(find.text('waiting.txt'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<BatchAction>(find.byType(BatchAction))
          .map((action) => action.label)
          .toList(),
      ['上传', '重命名', '修改上传目录', '删除', '重试'],
    );
    expect(
      find.byIcon(app_icons.Icons.drive_file_move_outline),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('download.zip'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<BatchAction>(find.byType(BatchAction))
          .map((action) => action.label)
          .toList(),
      ['分享', '删除', '重试'],
    );
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    app.dispose();
  });

  testWidgets('Windows 下载多选栏不显示多文件分享', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    AppEnvironment? app;
    try {
      final (environment, _) = await hostWithTasks(tester, [
        task(
          'd1',
          'download.zip',
          status: TransferStatus.done,
          kind: TransferKind.download,
        )..savedPath = '/tmp/download.zip',
      ], capabilities: PlatformCapabilities.windows);
      app = environment;
      await tester.tap(find.text('下载').hitTestable());
      await tester.pumpAndSettle();
      await tester.longPress(find.text('download.zip'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<BatchAction>(find.byType(BatchAction))
            .map((action) => action.label)
            .toList(),
        ['删除', '重试'],
      );
      expect(find.byTooltip('分享'), findsNothing);

      await tester.tap(find.byTooltip('退出多选'));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
      app?.dispose();
    }
  });

  testWidgets('批量重命名可返回配置，并在预览确认后一次修改任务名称', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task('u1', 'one_old.txt', status: TransferStatus.pending),
      task('u2', 'two_old.txt', status: TransferStatus.pending),
    ]);

    await tester.longPress(find.text('one_old.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('two_old.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('重命名'));
    await tester.pumpAndSettle();

    final dialogTitle = tester.widget<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('批量重命名'),
      ),
    );
    expect(dialogTitle.textAlign, TextAlign.start);

    final regexTile = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('正则表达式'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    final caseTile = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('区分大小写'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(regexTile.value, isFalse);
    expect(caseTile.value, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('upload-batch-rename-search')),
      'old',
    );
    await tester.enterText(
      find.byKey(const ValueKey('upload-batch-rename-replacement')),
      'new',
    );
    await tester.tap(find.byKey(const ValueKey('upload-batch-rename-preview')));
    await tester.pump();

    expect(find.byType(AnimatedSize), findsWidgets);
    expect(
      find.byKey(const ValueKey('upload-batch-rename-search')),
      findsOneWidget,
    );
    expect(find.text('one_old.txt → one_new.txt'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('upload-batch-rename-search')),
      findsNothing,
    );
    expect(find.text('one_old.txt → one_new.txt'), findsOneWidget);
    expect(find.text('two_old.txt → two_new.txt'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('upload-batch-rename-preview-list')),
          )
          .height,
      lessThan(300),
    );
    await tester.tap(find.byKey(const ValueKey('upload-batch-rename-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('upload-batch-rename-search')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('upload-batch-rename-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('upload-batch-rename-confirm')));
    await tester.pumpAndSettle();

    expect(manager.tasks.map((task) => task.name).toSet(), {
      'one_new.txt',
      'two_new.txt',
    });
    expect(
      manager.tasks.map((task) => task.status),
      everyElement(TransferStatus.pending),
    );
    expect(selectionBarOpacity(tester), 0);
    for (final name in ['one_new.txt', 'two_new.txt']) {
      expect(
        tester
            .widget<Md3ListItem>(
              find.ancestor(
                of: find.text(name),
                matching: find.byType(Md3ListItem),
              ),
            )
            .pulse,
        1,
        reason: '$name 修改成功后应闪动高亮',
      );
    }
    app.dispose();
  });

  testWidgets('单文件重命名预填当前名称并使用修改按钮', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task('u1', 'old.txt', status: TransferStatus.pending),
    ]);

    await openTransferRowMenu(tester, 'old.txt');
    await tester.tap(transferMenuItem('重命名'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('upload-rename-field')),
    );
    expect(field.controller?.text, 'old.txt');
    expect(find.byKey(const ValueKey('upload-rename-confirm')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('upload-rename-field')),
      'renamed.txt',
    );
    await tester.tap(find.byKey(const ValueKey('upload-rename-confirm')));
    await tester.pumpAndSettle();

    expect(manager.tasks.single.name, 'renamed.txt');
    expect(manager.tasks.single.status, TransferStatus.pending);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester
          .widget<Md3ListItem>(
            find.ancestor(
              of: find.text('renamed.txt'),
              matching: find.byType(Md3ListItem),
            ),
          )
          .pulse,
      1,
    );
    app.dispose();
  });
}
