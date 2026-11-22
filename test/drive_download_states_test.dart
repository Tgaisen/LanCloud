import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者

import 'support/drive_property_test_support.dart';

void main() {
  testWidgets('已添加下载的文件：属性弹窗下载按钮 checked，点击弹五项菜单', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    final manager = buildTransferManagerForEnvironment(app.environment);
    // 与页面一致的任务 refId：app.activeUid 在测试里是空串
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'a.zip',
          accountUid: '',
          refId: ':f1',
        )
        ..status = TransferStatus.done
        ..savedPath = '/tmp/a.zip',
    );

    await pumpDrive(tester, app, manager: manager);
    // 列表卡片上先有「已加入下载」小标记
    expect(find.byIcon(Icons.download_done), findsOneWidget);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    // 下载按钮变 checked、tooltip 变「已下载」
    expect(toggleButton(tester, '已下载').checked, isTrue);

    // 点它弹二级菜单：已完成 → 打开 / 分享可用，取消位换成删除记录，
    // 重新下载与「删除记录与文件」也可用
    await tester.tap(find.byTooltip('已下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final rows = tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .toList();
    expect(rows.map((r) => r.label).toList(), [
      '打开',
      '分享',
      '删除此条记录',
      '删除记录与文件',
      '重新下载',
    ]);
    expect(rows.every((r) => r.enabled), isTrue);

    // 删除这条任务记录：标记消失，按钮回到未选中（tooltip 变回「下载」）
    await tester.tap(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('删除此条记录'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(manager.tasks, isEmpty);
    expect(toggleButton(tester, '下载').checked, isFalse);
  });

  testWidgets('已添加下载的文件：菜单「删除记录与文件」连带删掉本地文件并恢复未下载', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    final manager = buildTransferManagerForEnvironment(app.environment);
    final dir = Directory.systemTemp.createTempSync('lancloud-del-mark');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/a.zip')..writeAsStringSync('x');
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'a.zip',
          accountUid: '',
          refId: ':f1',
        )
        ..status = TransferStatus.done
        ..savedPath = file.path,
    );

    await pumpDrive(tester, app, manager: manager);
    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    await tester.tap(find.byTooltip('已下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('删除记录与文件'),
      ),
    );
    // 点击 → 菜单收起（post-frame 回调）→ 选择回调里删文件、删记录
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(manager.tasks, isEmpty);
    // 文件是后台真实 I/O 删的：让真实事件循环跑两轮再回假时钟刷新续体
    for (var i = 0; i < 3 && file.existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(file.existsSync(), isFalse);
    // 恢复未下载原状
    expect(toggleButton(tester, '下载').checked, isFalse);
  });

  testWidgets('已添加下载但失败：属性弹窗显示「下载失败」+ 下载关闭图标', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    final manager = buildTransferManagerForEnvironment(app.environment);
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'a.zip',
          accountUid: '',
          refId: ':f1',
        )
        ..status = TransferStatus.failed
        ..error = '网络错误',
    );
    await pumpDrive(tester, app, manager: manager);
    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);

    expect(toggleButton(tester, '下载失败').checked, isTrue);
    // 弹窗里的图标位换成「下载关闭」（列表徽标仍是 download_done）
    expect(find.byIcon(Icons.file_download_off), findsOneWidget);
  });

  testWidgets('网盘文件属性弹窗：点下载先显示解析中环，解析失败恢复原状', (tester) async {
    final shareGate = GatedDriveClient();
    final directGate = GatedPublicClient();
    final app = FakeDriveApp(shareGate, publicClient: directGate);
    await pumpDrive(tester, app);
    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);

    // 分享信息回来之前：下载按钮置灰（原有行为）
    expect(toggleButton(tester, '下载').enabled, isFalse);
    shareGate.share.complete(
      ShareInfo(
        url: FakeDriveClient.fileUrl,
        pwd: 'abcd',
        isFile: true,
        name: 'a.zip',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(toggleButton(tester, '下载').enabled, isTrue);

    // 直链解析挂住：按钮位显示不确定态环 + 「解析中」（文案取 l10n，
    // 避免写死后被改文案带崩）
    final resolving = AppLocalizations.of(
      tester.element(find.byType(DrivePage)),
    ).resolving;
    // 页面里还有隐藏的多选条（同一个 tooltip），限定在属性弹窗里点
    await tester.tap(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.byTooltip('下载'),
      ),
    );
    await tester.pump();
    expect(find.byTooltip(resolving), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      isNull,
    );

    // 解析失败：回到「下载」原状（没有任务、没有环）
    directGate.gate.completeError(const LanzouException('网络异常'));
    await tester.pump();
    await tester.pump();
    expect(toggleButton(tester, '下载').enabled, isTrue);
    expect(find.byTooltip(resolving), findsNothing);
  });

  testWidgets('网盘文件属性弹窗：点「重新下载」立刻进入解析中状态', (tester) async {
    final directGate = GatedPublicClient();
    final app = FakeDriveApp(FakeDriveClient(), publicClient: directGate);
    final manager = buildTransferManagerForEnvironment(app.environment);
    manager.tasks.add(
      TransferTask(
        id: 'd1',
        kind: TransferKind.download,
        name: 'a.zip',
        accountUid: '',
        refId: ':f1',
      )..status = TransferStatus.failed,
    );
    await pumpDrive(tester, app, manager: manager);
    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);

    await tester.tap(find.byTooltip('下载失败'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('重新下载')),
    );
    // 点击 → 菜单收起（post-frame 回调）→ 选择回调里删旧任务并开始解析
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 旧任务已删、新任务还没入队：按钮位立刻换成不确定态环
    final resolving = AppLocalizations.of(
      tester.element(find.byType(DrivePage)),
    ).resolving;
    expect(manager.tasks, isEmpty);
    expect(find.byTooltip(resolving), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      isNull,
    );

    // 解析失败：恢复「下载」原状
    directGate.gate.completeError(const LanzouException('网络异常'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip(resolving), findsNothing);
    expect(toggleButton(tester, '下载').enabled, isTrue);
  });
}
