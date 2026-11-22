import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/file_open_result.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/transfer/transfer_issue.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/transfers_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/transfer_page_test_support.dart';

void main() {
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
      await pumpTransferUi(tester);
      expect(find.byType(M3eMenuRow), findsNothing);

      final doneCenter = tester.getCenter(doneRow);
      await tester.tap(
        doneRow,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await pumpTransferUi(tester);
      expect(transferMenuLabels(tester), ['删除此条记录']);
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
      transferTestHost(
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

    await openTransferRowMenu(tester, 'tool.apk');
    // 完成项：打开 / 分享 / 删除此条记录 / 删除记录与文件，且不给「重试」
    expect(transferMenuLabels(tester), ['打开', '分享', '删除此条记录', '删除记录与文件']);

    await tester.tap(transferMenuItem('打开'));
    await tester.pumpAndSettle();
    expect(opened, ['/tmp/tool.apk']);
    expect(openedNames, ['tool.apk']);

    await openTransferRowMenu(tester, 'tool.apk');
    await tester.tap(transferMenuItem('分享'));
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

  testWidgets('Windows 下载完成菜单使用资源管理器定位文案', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      TransferTask(
          id: 'd-win',
          kind: TransferKind.download,
          name: 'windows.zip',
          accountUid: '',
        )
        ..status = TransferStatus.done
        ..savedPath = '/tmp/windows.zip',
    ], capabilities: PlatformCapabilities.windows);
    await tester.tap(find.text('下载').hitTestable());
    await pumpTransferUi(tester);

    await openTransferRowMenu(tester, 'windows.zip');
    expect(transferMenuLabels(tester), ['打开', '打开所在文件夹', '删除此条记录', '删除记录与文件']);
    app.dispose();
  });

  testWidgets('iOS 下载完成菜单隐藏不可用的分享入口', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      TransferTask(
          id: 'd-ios',
          kind: TransferKind.download,
          name: 'ios.zip',
          accountUid: '',
        )
        ..status = TransferStatus.done
        ..savedPath = '/tmp/ios.zip',
    ], capabilities: PlatformCapabilities.ios);
    await tester.tap(find.text('下载').hitTestable());
    await pumpTransferUi(tester);

    await openTransferRowMenu(tester, 'ios.zip');
    expect(transferMenuLabels(tester), ['打开', '删除此条记录', '删除记录与文件']);
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
        transferTestHost(
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
    await tester.tap(find.text('下载').hitTestable());
    await tester.pumpAndSettle();

    await openTransferRowMenu(tester, 'bad.zip');
    // 失败项：不给打开 / 分享，给重试
    expect(transferMenuLabels(tester), ['重试', '删除此条记录', '删除记录与文件']);

    // 这个任务没有可用的直链（等价于重启后重启下载）：retry 会改成提示重新发起，
    // 正好用来确认菜单确实调到了 TransferManager.retry
    await tester.tap(transferMenuItem('重试'));
    await tester.pumpAndSettle();
    expect(failed.error, '应用重启后请重新发起下载');

    await openTransferRowMenu(tester, 'bad.zip');
    await tester.tap(transferMenuItem('删除记录与文件'));
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
    await tester.tap(find.text('上传').hitTestable());
    await tester.pumpAndSettle();

    // 失败的上传项：重试 + 删除此条记录，没有打开 / 分享 / 删除记录与文件
    await openTransferRowMenu(tester, 'fail.zip');
    expect(transferMenuLabels(tester), ['重试', '删除此条记录']);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 已完成的上传项：只剩删除此条记录（重试只给失败项）
    await openTransferRowMenu(tester, 'ok.zip');
    expect(transferMenuLabels(tester), ['删除此条记录']);
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

    await openTransferRowMenu(tester, 'large.zip');
    expect(transferMenuLabels(tester), ['重命名', '仍然上传', '删除此条记录']);
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
        transferTestHost(
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
}
