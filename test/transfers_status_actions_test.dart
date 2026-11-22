import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/ui/common.dart';

import 'support/transfer_page_test_support.dart';

void main() {
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
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 800);
    addTearDown(tester.view.reset);
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
}
