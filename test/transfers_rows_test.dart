import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/transfers_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/transfer_page_test_support.dart';

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
    // 上传运行中也显示进度，并与下载一样使用波浪动画。
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
      isTrue,
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
    await tester.tap(find.text('上传').hitTestable());
    await pumpTransferUi(tester);
    await tester.pump();

    expect(find.byTooltip('取消任务'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(find.byTooltip('暂停下载'), findsNothing);
    await tester.tap(find.byTooltip('取消任务'));
    await tester.pump();
    await tester.pump();
    expect(manager.tasks.map((task) => task.id), contains('u1'));
    expect(
      tester
          .widget<Md3ListItem>(
            find.ancestor(
              of: find.text('upload.zip'),
              matching: find.byType(Md3ListItem),
            ),
          )
          .removing,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 220));
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
    await tester.tap(find.byTooltip('取消任务'));
    await tester.pump();
    await tester.pump();
    expect(manager.tasks.map((task) => task.id), contains('d1'));
    expect(
      tester
          .widget<Md3ListItem>(
            find.ancestor(
              of: find.text('download.zip'),
              matching: find.byType(Md3ListItem),
            ),
          )
          .removing,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(manager.tasks.map((task) => task.id), isNot(contains('d1')));
    app.dispose();
  });
}
