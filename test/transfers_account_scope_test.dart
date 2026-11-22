import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/ui/common.dart';

import 'support/transfer_page_test_support.dart';

void main() {
  testWidgets('上传 Tab 只显示当前账号任务，切账号后立即换组', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      task(
        'a1',
        'account-a.txt',
        status: TransferStatus.pending,
        accountUid: 'a',
      ),
      task(
        'b1',
        'account-b.txt',
        status: TransferStatus.pending,
        accountUid: 'b',
      ),
    ]);
    app.accountState.store.accounts.addAll([
      Account(uid: 'a', cookie: 'cookie-a'),
      Account(uid: 'b', cookie: 'cookie-b'),
    ]);

    app.accountState.store.activeUid = 'a';
    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();
    expect(find.text('account-a.txt'), findsOneWidget);
    expect(find.text('account-b.txt'), findsNothing);

    app.accountState.store.activeUid = 'b';
    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();
    expect(find.text('account-a.txt'), findsNothing);
    expect(find.text('account-b.txt'), findsOneWidget);
    app.dispose();
  });

  testWidgets('待开始分栏的「全部上传」只启动当前账号任务', (tester) async {
    final accountA =
        TransferTask(
            id: 'a1',
            kind: TransferKind.upload,
            name: 'account-a.txt',
            accountUid: 'a',
            streamFactory: () => Stream<List<int>>.value(const [1]),
            sourceSize: 1,
          )
          ..status = TransferStatus.pending
          ..total = 1;
    final accountB =
        TransferTask(
            id: 'b1',
            kind: TransferKind.upload,
            name: 'account-b.txt',
            accountUid: 'b',
            streamFactory: () => Stream<List<int>>.value(const [1]),
            sourceSize: 1,
          )
          ..status = TransferStatus.pending
          ..total = 1;
    final (app, _) = await hostWithTasks(tester, [accountA, accountB]);
    app.settingsState.store.maxUploads = 0;
    app.accountState.store.accounts.addAll([
      Account(uid: 'a', cookie: 'cookie-a'),
      Account(uid: 'b', cookie: 'cookie-b'),
    ]);
    app.accountState.store.activeUid = 'a';
    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('transfers-upload-pending')));
    await tester.pumpAndSettle();

    expect(accountA.status, TransferStatus.queued);
    expect(accountB.status, TransferStatus.pending);
    app.dispose();
  });

  testWidgets('上传 Tab 的进行中分栏排在待开始前面', (tester) async {
    final (app, _) = await hostWithTasks(tester, [
      task('running', 'running.txt', status: TransferStatus.running),
      task('pending', 'pending.txt', status: TransferStatus.pending),
    ]);

    expect(
      tester.getTopLeft(find.text('进行中')).dy,
      lessThan(tester.getTopLeft(find.text('待开始')).dy),
    );
    app.dispose();
  });

  testWidgets('待开始菜单可修改上传目录并持久化目录名', (tester) async {
    final client = FolderPickerClient();
    final pending = task(
      'u1',
      'waiting.txt',
      status: TransferStatus.pending,
      accountUid: 'u1',
      folderId: 'old',
      folderName: '旧目录',
    )..total = 12;
    final (app, manager) = await hostWithTasks(tester, [
      pending,
    ], uploadClient: client);
    app.accountState.store.accounts.add(
      Account(uid: 'u1', cookie: 'cookie-u1'),
    );
    app.accountState.store.activeUid = 'u1';
    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();

    await openTransferRowMenu(tester, 'waiting.txt');
    await tester.tap(transferMenuItem('修改上传目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('根目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上传到此'));
    await tester.pumpAndSettle();

    expect(manager.tasks.single.folderId, '-1');
    expect(manager.tasks.single.folderName, '');
    expect(find.text('上传至 根目录 · 12 B'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester
          .widget<Md3ListItem>(
            find.ancestor(
              of: find.text('waiting.txt'),
              matching: find.byType(Md3ListItem),
            ),
          )
          .pulse,
      1,
    );
    app.dispose();
  });

  testWidgets('批量修改上传目录会作用于所有选中的待开始任务', (tester) async {
    final client = FolderPickerClient();
    final first = task(
      'u1',
      'one.txt',
      status: TransferStatus.pending,
      accountUid: 'u1',
      folderId: 'old',
      folderName: '旧目录',
    );
    final second = task(
      'u2',
      'two.txt',
      status: TransferStatus.pending,
      accountUid: 'u1',
      folderId: 'other',
      folderName: '另一个目录',
    );
    final unchanged = task(
      'u3',
      'unchanged.txt',
      status: TransferStatus.pending,
      accountUid: 'u1',
      folderId: '-1',
      folderName: '',
    );
    final (app, manager) = await hostWithTasks(tester, [
      first,
      second,
      unchanged,
    ], uploadClient: client);
    app.accountState.store.accounts.add(
      Account(uid: 'u1', cookie: 'cookie-u1'),
    );
    app.accountState.store.activeUid = 'u1';
    app.accountState.notifyAccountChanged();
    await tester.pumpAndSettle();

    await tester.longPress(find.text('one.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('two.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('unchanged.txt'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.byTooltip('修改上传目录'),
        matching: find.byType(BatchAction),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('上传到此'));
    await tester.pumpAndSettle();

    expect(manager.tasks.map((task) => task.folderId), everyElement('-1'));
    expect(selectionBarOpacity(tester), 0);
    for (final (name, pulse) in [
      ('one.txt', 1),
      ('two.txt', 1),
      ('unchanged.txt', 0),
    ]) {
      expect(
        tester
            .widget<Md3ListItem>(
              find.ancestor(
                of: find.text(name),
                matching: find.byType(Md3ListItem),
              ),
            )
            .pulse,
        pulse,
        reason: '$name 只有实际修改目录时才应闪动高亮',
      );
    }
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
