import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/file_open_result.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_issue.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/transfers_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

Widget _transferTestHost({
  required AppEnvironment app,
  required TransferManager manager,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      transferManagerProvider.overrideWithValue(manager),
      navigationAppearanceSettingsStateProvider.overrideWithValue(
        app.navigationAppearanceSettings,
      ),
      navigationStateProvider.overrideWithValue(app.navigation),
    ],
    child: child,
  );
}

TransferTask task(
  String id,
  String name, {
  required TransferStatus status,
  TransferKind kind = TransferKind.upload,
}) {
  return TransferTask(
    id: id,
    kind: kind,
    name: name,
    accountUid: '',
    localFilePath: '/tmp/$name',
  )..status = status;
}

Future<(AppEnvironment, TransferManager)> host(WidgetTester tester) async {
  final app = AppEnvironment();
  final manager = buildTransferManagerForEnvironment(app);
  manager.tasks.addAll([
    task('t1', 'a.zip', status: TransferStatus.failed),
    task('t2', 'b.zip', status: TransferStatus.failed),
    task('t3', 'c.zip', status: TransferStatus.done),
  ]);
  await tester.pumpWidget(
    _transferTestHost(
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
  await tester.tap(find.text('上传').hitTestable());
  await tester.pumpAndSettle();
  return (app, manager);
}

Future<(AppEnvironment, TransferManager)> hostWithTasks(
  WidgetTester tester,
  List<TransferTask> tasks,
) async {
  final app = AppEnvironment();
  final manager = buildTransferManagerForEnvironment(app);
  manager.tasks.addAll(tasks);
  await tester.pumpWidget(
    _transferTestHost(
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.tap(find.text('上传').hitTestable());
  await tester.pumpAndSettle();
  return (app, manager);
}

bool retryEnabled(WidgetTester tester) {
  final action = tester.widget<BatchAction>(
    // 图标按钮没有可见文字：标签就是 tooltip，按它定位
    find.ancestor(of: find.byTooltip('重试'), matching: find.byType(BatchAction)),
  );
  return action.onPressed != null;
}

/// 多选顶栏常驻在树里（靠透明度切换显示），用它判断多选是否真的打开。
double selectionBarOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('transfers-selection-appbar')),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

/// 把传输页作为独立页面（二级路由）打开，用于验证返回行为。
Future<AppEnvironment> pushTransfers(WidgetTester tester) async {
  final app = AppEnvironment();
  final manager = buildTransferManagerForEnvironment(app);
  manager.tasks.addAll([task('t1', 'a.zip', status: TransferStatus.failed)]);
  await tester.pumpWidget(
    _transferTestHost(
      app: app,
      manager: manager,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    // 独立路由形态（非底栏视图）：返回键 / 多选条按此分支
                    builder: (_) => const TransfersPage(),
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
  await tester.tap(find.text('上传').hitTestable());
  await tester.pumpAndSettle();
  return app;
}

int selectedTransferTab(WidgetTester tester) => tester
    .widget<M3eConnectedButtonGroup<int>>(
      find.byType(M3eConnectedButtonGroup<int>),
    )
    .selected;

void main() {
  testWidgets('失败副标题只显示错误详情，不重复上传下载前缀', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      task('u1', 'upload.zip', status: TransferStatus.failed)
        ..error = '失败：上传失败：server busy',
      task(
        'd1',
        'download.zip',
        status: TransferStatus.failed,
        kind: TransferKind.download,
      )..error = '失败：获取下载地址失败：HTTP 403',
    ]);

    expect(find.text('server busy'), findsOneWidget);
    expect(find.textContaining('上传失败：'), findsNothing);
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('HTTP 403'), findsOneWidget);
    expect(find.textContaining('下载失败：'), findsNothing);
    app.dispose();
  });

  testWidgets('传输列表按密集条目最小宽度铺两栏，不挤成三栏', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(856, 700);
    addTearDown(tester.view.reset);
    final (app, _) = await hostWithTasks(tester, [
      task('t1', 'a.zip', status: TransferStatus.done),
      task('t2', 'b.zip', status: TransferStatus.done),
      task('t3', 'c.zip', status: TransferStatus.done),
    ]);

    final rows = [
      for (final name in ['c.zip', 'b.zip', 'a.zip'])
        find.ancestor(of: find.text(name), matching: find.byType(Md3ListItem)),
    ];
    final first = tester.getTopLeft(rows[0]);
    final second = tester.getTopLeft(rows[1]);
    final third = tester.getTopLeft(rows[2]);
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(third.dy, greaterThan(first.dy));
    expect(
      tester.getSize(rows[0]).width,
      greaterThanOrEqualTo(kAdaptiveDenseListItemMinWidth),
    );
    app.dispose();
  });

  testWidgets('进行中条目的进度条与标题同宽：避让左侧图标与右侧按钮', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.add(
      task('t1', 'a.zip', status: TransferStatus.running)
        ..received = 1
        ..total = 2,
    );
    await tester.pumpWidget(
      _transferTestHost(
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
    // 上传运行中也显示进度，但不使用下载专属的波浪动画。
    await tester.pump();
    expect(selectedTransferTab(tester), 1, reason: '传输页默认应进入下载');
    await tester.tap(find.text('上传').hitTestable());
    await tester.pump(const Duration(milliseconds: 350));

    final title = tester.getRect(find.text('a.zip'));
    final bar = tester.getRect(find.byType(M3eLinearProgressIndicator));
    final cancel = tester.getRect(find.byTooltip('取消任务'));
    // 左边缘与标题对齐（在文字列里，自然避让 42dp 图标与 14dp 间距）
    expect(bar.left, closeTo(title.left, 0.5));
    // 右边缘不越过右侧按钮
    expect(bar.right, lessThanOrEqualTo(cancel.left));
    expect(bar.width, greaterThan(0));
    expect(
      tester
          .widget<M3eLinearProgressIndicator>(
            find.byType(M3eLinearProgressIndicator),
          )
          .wavy,
      isFalse,
    );
  });

  testWidgets('暂停的下载显示静态进度与继续按钮', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'paused.zip',
          accountUid: '',
        )
        ..status = TransferStatus.paused
        ..total = 100
        ..received = 40,
    );
    await tester.pumpWidget(
      _transferTestHost(
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
    final downloadTab = find.descendant(
      of: find.byType(M3eConnectedButtonGroup<int>),
      matching: find.byIcon(app_icons.Icons.download),
    );
    await tester.tap(downloadTab.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(find.byTooltip('继续下载'), findsOneWidget);
    expect(find.byTooltip('取消任务'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNothing);
    final progress = tester.widget<M3eLinearProgressIndicator>(
      find.byType(M3eLinearProgressIndicator),
    );
    expect(progress.value, closeTo(0.4, 0.001));
    expect(progress.wavy, isFalse);
  });

  testWidgets('恢复解析期间显示恢复中且暂停按钮禁用', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'paused.zip',
          accountUid: '',
          referer: 'https://example.com/share',
        )
        ..status = TransferStatus.paused
        ..total = 100
        ..received = 40,
    ]);
    app.settingsState.store.maxDownloads = 0;
    final resolvingStarted = Completer<void>();
    final resolving = Completer<DirectFile>();
    manager.debugResolveShare = (url, pwd) {
      resolvingStarted.complete();
      return resolving.future;
    };
    await tester.tap(find.text('下载').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byTooltip('继续下载'));
    await tester.pump();
    await resolvingStarted.future;
    await tester.pump();

    expect(manager.tasks.single.status, TransferStatus.resuming);
    expect(find.textContaining('恢复中'), findsOneWidget);
    expect(find.byTooltip('继续下载'), findsNothing);
    final pause = tester.widget<M3eIconButton>(
      find.ancestor(
        of: find.byTooltip('暂停下载'),
        matching: find.byType(M3eIconButton),
      ),
    );
    expect(pause.onPressed, isNull);
    final progress = tester.widget<M3eLinearProgressIndicator>(
      find.byType(M3eLinearProgressIndicator),
    );
    expect(progress.wavy, isFalse);

    resolving.complete(
      DirectFile(name: 'paused.zip', url: 'https://cdn.example/paused.zip'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(manager.tasks.single.status, TransferStatus.queued);
    final resumedPause = tester.widget<M3eIconButton>(
      find.ancestor(
        of: find.byTooltip('暂停下载'),
        matching: find.byType(M3eIconButton),
      ),
    );
    expect(resumedPause.onPressed, isNotNull);
    expect(
      tester
          .widget<M3eLinearProgressIndicator>(
            find.byType(M3eLinearProgressIndicator),
          )
          .wavy,
      isFalse,
    );
    app.dispose();
  });

  testWidgets('批量任务解析直链时显示解析中且暂停按钮禁用', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'resolving.zip',
          accountUid: '',
        )
        ..status = TransferStatus.resolving
        ..total = 100
        ..received = 40,
    ]);
    await tester.tap(find.text('下载').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('解析中'), findsOneWidget);
    final pause = tester.widget<M3eIconButton>(
      find.ancestor(
        of: find.byTooltip('暂停下载'),
        matching: find.byType(M3eIconButton),
      ),
    );
    expect(pause.onPressed, isNull);
    expect(
      tester
          .widget<M3eLinearProgressIndicator>(
            find.byType(M3eLinearProgressIndicator),
          )
          .wavy,
      isFalse,
    );
    app.dispose();
  });

  testWidgets('恢复后仍在排队的下载保留进度但停止波浪动画', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'queued.zip',
          accountUid: '',
        )
        ..status = TransferStatus.queued
        ..total = 100
        ..received = 40,
    );
    await tester.pumpWidget(
      _transferTestHost(
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
    final downloadTab = find.descendant(
      of: find.byType(M3eConnectedButtonGroup<int>),
      matching: find.byIcon(app_icons.Icons.download),
    );
    await tester.tap(downloadTab.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('排队中'), findsOneWidget);
    final progress = tester.widget<M3eLinearProgressIndicator>(
      find.byType(M3eLinearProgressIndicator),
    );
    expect(progress.value, closeTo(0.4, 0.001));
    expect(progress.wavy, isFalse);
  });

  testWidgets('正在保存的下载保留按钮占位但禁用暂停与取消', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'saving.zip',
          accountUid: '',
        )
        ..status = TransferStatus.saving
        ..total = 100
        ..received = 60,
    );
    await tester.pumpWidget(
      _transferTestHost(
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
    final downloadTab = find.descendant(
      of: find.byType(M3eConnectedButtonGroup<int>),
      matching: find.byIcon(app_icons.Icons.download),
    );
    await tester.tap(downloadTab.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('正在保存'), findsOneWidget);
    expect(find.byTooltip('继续下载'), findsNothing);
    expect(find.byTooltip('更多操作'), findsNothing);
    final pause = tester.widget<M3eIconButton>(
      find.ancestor(
        of: find.byTooltip('暂停下载'),
        matching: find.byType(M3eIconButton),
      ),
    );
    final cancel = tester.widget<M3eIconButton>(
      find.ancestor(
        of: find.byTooltip('取消任务'),
        matching: find.byType(M3eIconButton),
      ),
    );
    expect(pause.onPressed, isNull);
    expect(cancel.onPressed, isNull);
    final progress = tester.widget<M3eLinearProgressIndicator>(
      find.byType(M3eLinearProgressIndicator),
    );
    expect(progress.value, closeTo(0.6, 0.001));
    expect(progress.wavy, isFalse);
  });

  testWidgets('进行中任务使用取消按钮：上传仅一个，下载保留暂停', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.addAll([
      TransferTask(
          id: 'u1',
          kind: TransferKind.upload,
          name: 'upload.zip',
          accountUid: '',
          localFilePath: '/tmp/upload.zip',
        )
        ..status = TransferStatus.running
        ..received = 1
        ..total = 2,
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'download.zip',
          accountUid: '',
        )
        ..status = TransferStatus.running
        ..received = 1
        ..total = 2,
    ]);
    await tester.pumpWidget(
      _transferTestHost(
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
    await tester.tap(find.text('上传').hitTestable());
    await tester.pumpAndSettle();
    await tester.pump();

    expect(find.byTooltip('取消任务'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(find.byTooltip('暂停下载'), findsNothing);
    await tester.tap(find.byTooltip('取消任务'));
    await tester.pump();
    expect(manager.tasks.map((task) => task.id), isNot(contains('u1')));

    final downloadTab = find.descendant(
      of: find.byType(M3eConnectedButtonGroup<int>),
      matching: find.byIcon(app_icons.Icons.download),
    );
    await tester.tap(downloadTab.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byTooltip('暂停下载'), findsOneWidget);
    expect(find.byTooltip('取消任务'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(
      tester
          .widget<M3eLinearProgressIndicator>(
            find.byType(M3eLinearProgressIndicator),
          )
          .wavy,
      isTrue,
    );
    app.dispose();
  });

  testWidgets('独立页面：多选时返回只退出多选，不退出页面', (tester) async {
    final app = await pushTransfers(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isFalse);
    expect(find.byType(TransfersPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TransfersPage), findsNothing);
  });

  testWidgets('点击上传条目不做任何反应：长按才进入多选', (tester) async {
    final (app, _) = await host(tester);

    // 上传条目点不开，点击不做任何反应，也不会进入多选
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isFalse);
    expect(selectionBarOpacity(tester), 0);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(selectionBarOpacity(tester), 1);
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(app.navigation.selectionMode, isTrue);
  });

  // 回归：播报必须挂在「真正进入多选」上。多选条在页面里常驻（透明度切换），
  // 之前把播报放进多选条 initState，导致从首页打开传输页/收藏就误读「进入多选」，
  // 而网盘页真正进入多选反而没提示。
  testWidgets('页面打开不播报「进入多选」，长按进入时才播报一次', (tester) async {
    final announcements = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          final event = message as Map<dynamic, dynamic>;
          if (event['type'] == 'announce') {
            announcements.add(
              (event['data'] as Map<dynamic, dynamic>)['message'] as String,
            );
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    // 打开传输页（多选条已经建在树里）不该播报
    final app = await pushTransfers(tester);
    // 等过播报的延迟窗口：页面构建本身不能产生任何播报
    await tester.pump(const Duration(milliseconds: 400));
    expect(announcements, isEmpty);

    // 长按进入多选：播报一次
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(announcements, ['进入多选']);

    // 已在多选里继续长按其它条目不再重复播报
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(announcements, ['进入多选']);

    // 退出多选后再收尾，避免页面 dispose 时去动已销毁的控制器
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    app.dispose();
  });

  // 行内操作（取消 / ⋯）多选时只隐藏不改变布局：条目高度不变。
  testWidgets('多选隐藏行内操作但保留占位：条目高度不变', (tester) async {
    final (app, _) = await host(tester);
    final item = find.ancestor(
      of: find.text('a.zip'),
      matching: find.byType(Md3ListItem),
    );
    final height = tester.getSize(item).height;
    final more = find.descendant(of: item, matching: find.byTooltip('更多操作'));
    expect(more, findsOneWidget);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isTrue);
    expect(tester.getSize(item).height, height);
    expect(
      tester
          .widget<HideKeepingSpace>(
            find.ancestor(of: more, matching: find.byType(HideKeepingSpace)),
          )
          .hidden,
      isTrue,
    );

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(tester.getSize(item).height, height);
    expect(more, findsOneWidget);
    app.dispose();
  });

  testWidgets('进入多选后各分栏操作变为选择，并追加选中该栏全部任务', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 1600);
    addTearDown(tester.view.reset);
    final (app, _) = await hostWithTasks(tester, [
      task('u1', 'pending.txt', status: TransferStatus.pending),
      task('u2', 'running.txt', status: TransferStatus.running),
      task('u3', 'skipped.txt', status: TransferStatus.skipped),
      task('u4', 'failed.txt', status: TransferStatus.failed),
      task('u5', 'done.txt', status: TransferStatus.done),
    ]);

    await tester.longPress(find.text('pending.txt'));
    await tester.pumpAndSettle();

    for (final key in [
      'transfers-select-pending',
      'transfers-select-active',
      'transfers-select-skipped',
      'transfers-select-failed',
      'transfers-select-finished',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('选择'), findsNWidgets(5));
    expect(find.byKey(const ValueKey('transfers-clear-pending')), findsNothing);
    expect(find.byKey(const ValueKey('transfers-clear-skipped')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transfers-select-failed')));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transfers-select-finished')));
    await tester.pumpAndSettle();
    expect(find.text('已选择 3 项'), findsOneWidget);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfers-clear-finished')),
      findsOneWidget,
    );
    app.dispose();
  });

  testWidgets('非紧凑分栏的上下留白不受右侧操作影响', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionHeader(
            title: '进行中',
            count: 1,
            actions: [TextButton(onPressed: () {}, child: const Text('全部暂停'))],
          ),
        ),
      ),
    );

    final header = tester.widget<SectionHeader>(find.byType(SectionHeader));
    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(SectionHeader),
            matching: find.byType(Padding),
          )
          .first,
    );

    expect(header.compact, isFalse);
    expect(padding.padding, const EdgeInsets.fromLTRB(4, 16, 4, 8));
  });

  // 多选期间切换上传 / 下载：不禁用按钮组，切换后自动退出多选。
  testWidgets('多选时切换上传 / 下载会退出多选', (tester) async {
    await host(tester);
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(selectionBarOpacity(tester), 1);

    // 下载在前；按钮组内部会重复构建 label（用于测量/动画），按位置点左侧。
    final group = tester.getRect(find.byType(M3eConnectedButtonGroup<int>));
    expect(
      tester
          .widget<M3eConnectedButtonGroup<int>>(
            find.byType(M3eConnectedButtonGroup<int>),
          )
          .values,
      const [1, 0],
    );
    await tester.tapAt(
      Offset(group.left + group.width * 0.25, group.center.dy),
    );
    await tester.pumpAndSettle();

    expect(selectionBarOpacity(tester), 0, reason: '切换 tab 后应退出多选');
    expect(find.text('暂无下载任务'), findsOneWidget);
  });

  // 取消最后一个选中项 → 自动退出多选（不再停在「已选择 0 项」）。
  testWidgets('选中数归零自动退出多选', (tester) async {
    await host(tester);
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(selectionBarOpacity(tester), 1);

    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();

    expect(selectionBarOpacity(tester), 0);
  });

  // 顶栏只保留多选入口；分栏右侧负责各自的清空操作。
  testWidgets('顶栏多选按钮点击进入多选并播报', (tester) async {
    final announcements = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          final event = message as Map<dynamic, dynamic>;
          if (event['type'] == 'announce') {
            announcements.add(
              (event['data'] as Map<dynamic, dynamic>)['message'] as String,
            );
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    final (app, _) = await host(tester);

    final multiSelect = find.byTooltip('多选');
    expect(multiSelect, findsOneWidget);
    expect(find.byTooltip('清除已完成'), findsNothing);

    await tester.tap(multiSelect);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.navigation.selectionMode, isTrue);
    // 先用顶栏进多选（未选中任何条目），也要有提示
    expect(announcements, ['进入多选']);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isFalse);
    app.dispose();
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
    expect(app.navigation.selectionMode, isFalse);
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

    await tester.tap(find.byTooltip('删除'));
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
    expect(app.navigation.selectionMode, isFalse);
    app.dispose();
  });

  testWidgets('上传失败与已完成分栏分别清空各自记录', (tester) async {
    final (app, manager) = await host(tester);

    expect(find.text('失败'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transfers-clear-finished')));
    await tester.pumpAndSettle();
    expect(find.text('清空已完成任务'), findsOneWidget);
    expect(find.text('将清空全部 1 条已完成的上传任务记录，继续吗？'), findsOneWidget);
    expect(find.text('同时删除文件'), findsNothing);

    // 取消：记录原样
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(manager.tasks, hasLength(3));

    // 清空已完成只删 done，失败记录仍保留。
    await tester.tap(find.byKey(const ValueKey('transfers-clear-finished')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-delete-confirm')));
    await tester.pumpAndSettle();
    expect(manager.tasks.map((task) => task.status), [
      TransferStatus.failed,
      TransferStatus.failed,
    ]);
    expect(find.text('c.zip'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transfers-clear-failed')));
    await tester.pumpAndSettle();
    expect(find.text('清空失败任务'), findsOneWidget);
    expect(find.text('将清空全部 2 条失败任务记录，继续吗？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transfer-delete-confirm')));
    await tester.pumpAndSettle();
    expect(manager.tasks, isEmpty);
    expect(find.text('暂无上传任务'), findsOneWidget);
    app.dispose();
  });

  testWidgets('已完成条目副标题只显示文件大小', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      task('u1', 'done.zip', status: TransferStatus.done)
        ..total = 10 * 1024 * 1024,
    ]);

    expect(find.text('10.0 MB'), findsOneWidget);
    expect(find.textContaining('已完成 ·'), findsNothing);
    app.dispose();
  });

  testWidgets('进行中、被跳过、失败与已完成分栏均按新任务在前排序', (tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final (app, _) = await hostWithTasks(tester, [
      task('a-old', 'active-old.zip', status: TransferStatus.running),
      task('a-new', 'active-new.zip', status: TransferStatus.queued),
      task('s-old', 'skipped-old.zip', status: TransferStatus.skipped),
      task('s-new', 'skipped-new.zip', status: TransferStatus.skipped),
      task('f-old', 'failed-old.zip', status: TransferStatus.failed),
      task('f-new', 'failed-new.zip', status: TransferStatus.failed),
      task('c-old', 'completed-old.zip', status: TransferStatus.done),
      task('c-new', 'completed-new.zip', status: TransferStatus.done),
    ]);

    double top(String name) => tester.getTopLeft(find.text(name)).dy;

    expect(top('active-new.zip'), lessThan(top('active-old.zip')));
    expect(top('skipped-new.zip'), lessThan(top('skipped-old.zip')));
    expect(top('failed-new.zip'), lessThan(top('failed-old.zip')));
    expect(top('completed-new.zip'), lessThan(top('completed-old.zip')));
    app.dispose();
  });

  testWidgets('上传进行中分栏：全部取消先确认且不显示删除文件', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task('u1', 'running.zip', status: TransferStatus.running),
      task('u2', 'queued.zip', status: TransferStatus.queued),
      task('u3', 'finished.zip', status: TransferStatus.done),
    ]);

    await tester.tap(find.byKey(const ValueKey('transfers-cancel-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('取消进行中任务'), findsOneWidget);
    expect(find.text('将取消并移除全部 2 个进行中的上传任务，继续吗？'), findsOneWidget);
    expect(find.text('同时删除文件'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transfer-delete-confirm')));
    await tester.pumpAndSettle();
    expect(manager.tasks.map((item) => item.id), ['u3']);
    expect(find.text('running.zip'), findsNothing);
    expect(find.text('finished.zip'), findsOneWidget);
    app.dispose();
  });

  testWidgets('下载进行中分栏：部分暂停时只显示全部恢复', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      TransferTask(
        id: 'd1',
        kind: TransferKind.download,
        name: 'running.zip',
        accountUid: '',
        url: 'https://cdn.example/running.zip',
      )..status = TransferStatus.running,
      TransferTask(
        id: 'd2',
        kind: TransferKind.download,
        name: 'paused.zip',
        accountUid: '',
        url: 'https://cdn.example/paused.zip',
      )..status = TransferStatus.paused,
    ]);
    app.settingsState.store.maxDownloads = 0;
    await tester.tap(find.text('下载').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('transfers-pause-all')), findsNothing);
    expect(find.byKey(const ValueKey('transfers-cancel-all')), findsNothing);
    expect(find.byKey(const ValueKey('transfers-resume-all')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transfers-resume-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(manager.tasks.last.status, TransferStatus.queued);
    app.dispose();
  });

  testWidgets('下载进行中分栏：全部暂停后并排显示取消和恢复', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      TransferTask(
        id: 'd1',
        kind: TransferKind.download,
        name: 'running.zip',
        accountUid: '',
      )..status = TransferStatus.running,
      TransferTask(
        id: 'd2',
        kind: TransferKind.download,
        name: 'queued.zip',
        accountUid: '',
      )..status = TransferStatus.queued,
    ]);
    await tester.tap(find.text('下载').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final pauseButton = find.byKey(const ValueKey('transfers-pause-all'));
    expect(pauseButton, findsOneWidget);
    expect(
      tester.widget<TextButton>(pauseButton).style?.minimumSize?.resolve({}),
      const Size(0, 32),
    );
    final header = find.ancestor(
      of: pauseButton,
      matching: find.byType(SectionHeader),
    );
    expect(tester.getSize(header).height, lessThanOrEqualTo(48));
    await tester.tap(pauseButton);
    await tester.pumpAndSettle();

    expect(manager.tasks.map((item) => item.status), [
      TransferStatus.paused,
      TransferStatus.paused,
    ]);
    expect(find.byKey(const ValueKey('transfers-cancel-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('transfers-resume-all')), findsOneWidget);
    app.dispose();
  });

  testWidgets('下载进行中分栏：全部取消不显示文件选项并默认删除文件', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lancloud-cancel-active');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/paused.zip');
    file.writeAsStringSync('partial');
    final (app, manager) = await hostWithTasks(tester, [
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'paused.zip',
          accountUid: '',
        )
        ..status = TransferStatus.paused
        ..savedPath = file.path,
    ]);
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('transfers-cancel-all')));
    await tester.pumpAndSettle();
    expect(find.text('将取消并移除全部 1 个进行中的下载任务，继续吗？'), findsOneWidget);
    expect(find.text('同时删除文件'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('transfer-delete-confirm')));
    await tester.pump();
    expect(manager.tasks, isEmpty);

    for (var i = 0; i < 3 && file.existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(file.existsSync(), isFalse);
    app.dispose();
  });

  testWidgets('下载已完成分栏：可清空记录并同时删除文件', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lancloud-clear-finished');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/finished.zip');
    file.writeAsStringSync('downloaded');
    final (app, manager) = await hostWithTasks(tester, [
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'finished.zip',
          accountUid: '',
        )
        ..status = TransferStatus.done
        ..savedPath = file.path,
    ]);
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('transfers-clear-finished')));
    await tester.pumpAndSettle();
    expect(find.text('同时删除文件'), findsOneWidget);
    await tester.tap(find.text('同时删除文件'));
    await tester.tap(find.byKey(const ValueKey('transfer-delete-confirm')));
    await tester.pump();

    expect(manager.tasks, isEmpty);
    for (var i = 0; i < 3 && file.existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(file.existsSync(), isFalse);
    app.dispose();
  });

  /// 打开某一行（按文件名定位）的 ⋯ 菜单。
  Future<void> openRowMenu(WidgetTester tester, String name) async {
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(Md3ListItem),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('更多操作')),
    );
    await tester.pumpAndSettle();
  }

  /// 菜单里的项（按显示顺序）。多选操作栏里也有「重试 / 删除」同文案的按钮，
  /// 所以这里只认菜单自己的行。
  List<String> menuLabels(WidgetTester tester) => tester
      .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
      .map((row) => row.label)
      .toList();

  Finder menuItem(String label) =>
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text(label));

  testWidgets('Android 外接鼠标：右键菜单仅对带 ⋯ 的已结束任务开放', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final (app, _) = await hostWithTasks(tester, [
      task('running', 'running.zip', status: TransferStatus.running)
        ..received = 40
        ..total = 100,
      task('done', 'done.zip', status: TransferStatus.done),
    ]);
    final runningRow = find.ancestor(
      of: find.text('running.zip'),
      matching: find.byType(Md3ListItem),
    );
    final doneRow = find.ancestor(
      of: find.text('done.zip'),
      matching: find.byType(Md3ListItem),
    );

    try {
      expect(
        find.descendant(of: runningRow, matching: find.byTooltip('更多操作')),
        findsNothing,
      );
      expect(
        find.descendant(of: doneRow, matching: find.byTooltip('更多操作')),
        findsOneWidget,
      );

      await tester.tap(
        runningRow,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byType(M3eMenuRow), findsNothing);

      final doneCenter = tester.getCenter(doneRow);
      await tester.tap(
        doneRow,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(menuLabels(tester), ['删除此条记录']);
      final menuCard = tester.getRect(
        find.byKey(const ValueKey('m3e-menu-card')),
      );
      expect(menuCard.topLeft, doneCenter);
    } finally {
      app.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('下载完成的项目：点击条目打开文件，⋯ 菜单给打开 / 分享 / 删除', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
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
    final opened = <String>[];
    final openedNames = <String?>[];
    final shared = <MethodCall>[];
    const shareChannel = MethodChannel('lancloud/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shared.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );
    await tester.pumpWidget(
      _transferTestHost(
        app: app,
        manager: manager,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: TransfersPage(
            openFile: (path, {String? name}) async {
              opened.add(path);
              openedNames.add(name);
              return const FileOpenResult.success();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // MD3E 按钮组会额外渲染一份「离屏测量」副本（IgnorePointer 包着），
    // 所以按文字找按钮时要排掉不可点击的那份。
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('tool.apk'), findsOneWidget);
    expect(find.byTooltip('安装'), findsNothing);
    // 打开 / 分享都收进 ⋯ 菜单，行内不再单独给按钮
    expect(find.byTooltip('打开'), findsNothing);
    expect(find.byTooltip('分享').hitTestable(), findsNothing);

    await openRowMenu(tester, 'tool.apk');
    // 完成项：打开 / 分享 / 删除此条记录 / 删除记录与文件，且不给「重试」
    expect(menuLabels(tester), ['打开', '分享', '删除此条记录', '删除记录与文件']);

    await tester.tap(menuItem('打开'));
    await tester.pumpAndSettle();
    expect(opened, ['/tmp/tool.apk']);
    expect(openedNames, ['tool.apk']);

    await openRowMenu(tester, 'tool.apk');
    await tester.tap(menuItem('分享'));
    await tester.pumpAndSettle();
    expect(shared, hasLength(1));
    expect(shared.single.method, 'shareFile');
    expect(shared.single.arguments['path'], '/tmp/tool.apk');
    // APK 用包安装类型，分享到系统面板后才能被识别
    expect(
      shared.single.arguments['mime'],
      'application/vnd.android.package-archive',
    );

    await tester.tap(find.text('tool.apk'));
    await tester.pumpAndSettle();
    expect(opened, ['/tmp/tool.apk', '/tmp/tool.apk']);
    expect(openedNames, ['tool.apk', 'tool.apk']);
    // 点击条目只打开文件，不会进入多选
    expect(selectionBarOpacity(tester), 0);
    app.dispose();
  });

  testWidgets('下载多选分享一次提交全部已完成文件，忽略不可分享任务', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task(
        'd1',
        'one.zip',
        status: TransferStatus.done,
        kind: TransferKind.download,
      )..savedPath = '/tmp/one.zip',
      task(
        'd2',
        'two.apk',
        status: TransferStatus.done,
        kind: TransferKind.download,
      )..savedPath = '/tmp/two.apk',
      task(
        'd3',
        'failed.zip',
        status: TransferStatus.failed,
        kind: TransferKind.download,
      )..savedPath = '/tmp/failed.zip',
    ]);
    final shared = <MethodCall>[];
    const shareChannel = MethodChannel('lancloud/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shared.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );

    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('one.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('two.apk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('failed.zip'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.ancestor(
        of: find.byTooltip('分享'),
        matching: find.byType(BatchAction),
      ),
    );
    await tester.pumpAndSettle();

    expect(shared, hasLength(1));
    expect(shared.single.method, 'shareFiles');
    expect(
      shared.single.arguments['paths'],
      unorderedEquals(['/tmp/one.zip', '/tmp/two.apk']),
    );
    expect(shared.single.arguments['subject'], '分享');
    expect(selectionBarOpacity(tester), 0);
    expect(manager.tasks, hasLength(3));
    app.dispose();
  });

  for (final (failure, message) in <(FileOpenFailure, String)>[
    (FileOpenFailure.fileNotFound, '文件不存在，可能已被移动或删除'),
    (FileOpenFailure.permissionDenied, '文件访问权限已失效；重新选择下载目录只影响之后的任务，请重新下载该文件'),
    (FileOpenFailure.noAssociatedApp, '没有可打开此文件的应用'),
    (FileOpenFailure.systemError, '系统无法打开该文件，请稍后重试'),
  ]) {
    testWidgets('下载打开失败时显示 $failure 对应提示', (tester) async {
      final app = AppEnvironment();
      final manager = buildTransferManagerForEnvironment(app);
      manager.tasks.add(
        TransferTask(
            id: 'd1',
            kind: TransferKind.download,
            name: 'broken.zip',
            accountUid: '',
          )
          ..status = TransferStatus.done
          ..savedPath = '/tmp/broken.zip',
      );
      await tester.pumpWidget(
        _transferTestHost(
          app: app,
          manager: manager,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: TransfersPage(
              openFile: (path, {String? name}) async =>
                  FileOpenResult.failed(failure),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final downloadTab = find.descendant(
        of: find.byType(M3eConnectedButtonGroup<int>),
        matching: find.byIcon(app_icons.Icons.download),
      );
      await tester.tap(downloadTab.first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('broken.zip'));
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      app.dispose();
    });
  }

  testWidgets('失败下载的 ⋯ 菜单：重试可用，删除记录与文件连带删掉本地文件', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    // widget 测试跑在 FakeAsync 里：测试体内的文件 I/O 必须走同步接口，
    // 否则 await 永远等不到真实事件循环上的回调
    final dir = Directory.systemTemp.createTempSync('lancloud-transfers');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/bad.zip');
    file.writeAsStringSync('partial');
    final failed =
        TransferTask(
            id: 'f1',
            kind: TransferKind.download,
            name: 'bad.zip',
            accountUid: '',
          )
          ..status = TransferStatus.failed
          ..error = '网络错误'
          ..savedPath = file.path;
    manager.tasks.add(failed);
    await tester.pumpWidget(
      _transferTestHost(
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
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();

    await openRowMenu(tester, 'bad.zip');
    // 失败项：不给打开 / 分享，给重试
    expect(menuLabels(tester), ['重试', '删除此条记录', '删除记录与文件']);

    // 这个任务没有可用的直链（等价于重启后重启下载）：retry 会改成提示重新发起，
    // 正好用来确认菜单确实调到了 TransferManager.retry
    await tester.tap(menuItem('重试'));
    await tester.pumpAndSettle();
    expect(failed.error, '应用重启后请重新发起下载');

    await openRowMenu(tester, 'bad.zip');
    await tester.tap(menuItem('删除记录与文件'));
    // 先播删除动画（220ms）再真正移除
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();
    expect(manager.tasks, isEmpty);
    expect(find.text('bad.zip'), findsNothing);
    // 文件是后台真实 I/O 删的：让真实事件循环跑两轮再回假时钟刷新续体
    for (var i = 0; i < 3 && file.existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(file.existsSync(), isFalse);
    app.dispose();
  });

  testWidgets('上传条目的 ⋯ 菜单只有重试（失败时）与删除此条记录', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.addAll([
      task('u1', 'fail.zip', status: TransferStatus.failed),
      task('u2', 'ok.zip', status: TransferStatus.done),
    ]);
    await tester.pumpWidget(
      _transferTestHost(
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
    await tester.tap(find.text('上传').hitTestable());
    await tester.pumpAndSettle();

    // 失败的上传项：重试 + 删除此条记录，没有打开 / 分享 / 删除记录与文件
    await openRowMenu(tester, 'fail.zip');
    expect(menuLabels(tester), ['重试', '删除此条记录']);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 已完成的上传项：只剩删除此条记录（重试只给失败项）
    await openRowMenu(tester, 'ok.zip');
    expect(menuLabels(tester), ['删除此条记录']);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    app.dispose();
  });

  testWidgets('被跳过的上传单独分栏，菜单可仍然上传或删除记录', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task('u1', 'large.zip', status: TransferStatus.skipped)
        ..error = '此类文件不允许上传'
        ..total = 10 * 1024 * 1024,
    ]);

    expect(find.text('被跳过'), findsWidgets);
    expect(find.text('此类文件不允许上传'), findsOneWidget);
    expect(find.textContaining('10.0 MB'), findsNothing);
    expect(
      find.byKey(const ValueKey('transfers-clear-skipped')),
      findsOneWidget,
    );

    await openRowMenu(tester, 'large.zip');
    expect(menuLabels(tester), ['重命名', '仍然上传', '删除此条记录']);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('transfers-clear-skipped')));
    await tester.pumpAndSettle();
    expect(find.text('将清空全部 1 条被跳过的上传任务记录，继续吗？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transfer-delete-confirm')));
    await tester.pumpAndSettle();
    expect(manager.tasks, isEmpty);
    expect(find.text('large.zip'), findsNothing);
    app.dispose();
  });

  testWidgets('被跳过副标题跟随界面语言切换', (tester) async {
    final app = AppEnvironment();
    final manager = buildTransferManagerForEnvironment(app);
    manager.tasks.add(
      task('u1', 'unsupported.bin', status: TransferStatus.skipped)
        ..error = const TransferIssue(TransferIssueCode.skippedUnsupported)
            .encode(),
    );

    Future<void> pumpLocale(Locale locale) async {
      await tester.pumpWidget(
        _transferTestHost(
          app: app,
          manager: manager,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            home: const TransfersPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(locale.languageCode == 'zh' ? '上传' : 'Upload').hitTestable(),
      );
      await tester.pumpAndSettle();
    }

    await pumpLocale(const Locale('zh'));
    expect(find.text('此类文件不允许上传'), findsOneWidget);

    await pumpLocale(const Locale('en'));
    expect(find.text('This type of file cannot be uploaded'), findsOneWidget);
    app.dispose();
  });

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
      _transferTestHost(
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
        _transferTestHost(
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
      _transferTestHost(
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

  testWidgets('待开始上传单独分栏，行内提供上传按钮与重命名/取消菜单', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
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

    await openRowMenu(tester, 'waiting.txt');
    expect(menuLabels(tester), ['重命名', '取消上传']);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
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

  testWidgets('上传多选栏为改名/上传/删除/重试，下载多选栏为分享/删除/重试', (tester) async {
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
      ['重命名', '上传', '删除', '重试'],
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
      ]);
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
    app.dispose();
  });

  testWidgets('单文件重命名预填当前名称并使用修改按钮', (tester) async {
    final (app, manager) = await hostWithTasks(tester, [
      task('u1', 'old.txt', status: TransferStatus.pending),
    ]);

    await openRowMenu(tester, 'old.txt');
    await tester.tap(menuItem('重命名'));
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
    app.dispose();
  });

  testWidgets('批量上传只启动选中的待开始任务', (tester) async {
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
    final skipped = task('u3', 'skip.txt', status: TransferStatus.skipped);
    final (app, manager) = await hostWithTasks(tester, [
      pendingOne,
      pendingTwo,
      skipped,
    ]);
    app.settingsState.store.maxUploads = 0;
    app.accountState.store.accounts.add(
      Account(uid: 'u1', cookie: 'phpdisk_info=x'),
    );
    app.accountState.store.activeUid = 'u1';

    await tester.longPress(find.text('one.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('two.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('skip.txt'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.byTooltip('上传'),
        matching: find.byType(BatchAction),
      ),
    );
    await tester.pumpAndSettle();

    expect(pendingOne.status, TransferStatus.queued);
    expect(pendingTwo.status, TransferStatus.queued);
    expect(skipped.status, TransferStatus.skipped);
    expect(selectionBarOpacity(tester), 0);
    app.dispose();
  });
}
