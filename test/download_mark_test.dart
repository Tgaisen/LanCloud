import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/download_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('downloadMarkOf：网盘按 refId、分享按 referer 匹配，取最近一条', () {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final manager = buildTransferManagerForEnvironment(environment);
    final older = TransferTask(
      id: 'd1',
      kind: TransferKind.download,
      name: 'a.zip',
      accountUid: '',
      refId: '1:f1',
      referer: 'https://share.example/x',
    )..status = TransferStatus.done;
    final newer = TransferTask(
      id: 'd2',
      kind: TransferKind.download,
      name: 'a.zip',
      accountUid: '',
      refId: '1:f1',
    )..status = TransferStatus.running;
    // 上传任务哪怕 referer 相同也不算
    final upload = TransferTask(
      id: 'u1',
      kind: TransferKind.upload,
      name: 'a.zip',
      accountUid: '',
      referer: 'https://share.example/x',
    );
    manager.tasks.addAll([older, newer, upload]);

    expect(manager.downloadMarkOf('1:f1')?.id, 'd2');
    expect(manager.downloadMarkOf('https://share.example/x')?.id, 'd1');
    expect(manager.downloadMarkOf(''), isNull);
    expect(manager.downloadMarkOf('1:f9'), isNull);
  });

  test('downloadMarkOf：忽略已取消的任务', () {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final manager = buildTransferManagerForEnvironment(environment);
    final task = TransferTask(
      id: 'd1',
      kind: TransferKind.download,
      name: 'a.zip',
      accountUid: '',
      refId: '1:f1',
    )..status = TransferStatus.running;
    manager.tasks.add(task);

    expect(manager.downloadMarkOf('1:f1'), isNotNull);
    manager.cancel('d1');
    expect(manager.downloadMarkOf('1:f1'), isNull);
  });

  test('marksRevision：入队 / 取消 / 删除任务会自增（供列表低频重建）', () {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final manager = buildTransferManagerForEnvironment(environment);
    final before = manager.marksRevision.value;

    manager.addDownload(
      url: 'https://cdn.example/a.zip',
      name: 'a.zip',
      refId: '1:f1',
    );
    // 入队 + 开始跑各一次；下载中的进度更新不会自增（列表不跟着抖）
    expect(manager.marksRevision.value, before + 2);

    final task = manager.tasks.last;
    manager.cancel(task.id);
    expect(manager.marksRevision.value, before + 3);
    manager.removeTask(task.id);
    expect(manager.marksRevision.value, before + 4);
  });

  testWidgets('DownloadMarkIcon：有任务时显示，取消后消失', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final manager = buildTransferManagerForEnvironment(environment);
    final task = TransferTask(
      id: 'd1',
      kind: TransferKind.download,
      name: 'a.zip',
      accountUid: '',
      refId: '1:f1',
    )..status = TransferStatus.running;
    manager.tasks.add(task);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [transferManagerProvider.overrideWithValue(manager)],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: DownloadMarkIcon(markKey: '1:f1')),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.download_done), findsOneWidget);

    manager.cancel('d1');
    await tester.pump();
    expect(find.byIcon(Icons.download_done), findsNothing);
  });

  testWidgets('DownloadMarkIcon：没有 Provider 时静默不显示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: DownloadMarkIcon(markKey: '1:f1')),
        ),
      ),
    );
    expect(find.byIcon(Icons.download_done), findsNothing);
  });
}
