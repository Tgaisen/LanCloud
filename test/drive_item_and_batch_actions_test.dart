import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;

import 'support/drive_property_test_support.dart';

void main() {
  testWidgets('网盘条目鼠标右键：菜单从鼠标坐标展开', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);
    final file = find.text('a.zip');
    final pointer = tester.getCenter(file);

    await tester.tap(
      file,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final menu = tester.getRect(find.byKey(const ValueKey('m3e-menu-card')));
    expect(menu.topLeft, pointer);
    expect(find.byType(M3eMenuRow), findsWidgets);
  });

  testWidgets('网盘页文件 ⋯ 菜单：重命名与简介拆分，属性打开属性弹窗', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件操作'));
    // ⋯ 菜单是弹簧展开的：pump 到它长出来（真机一两帧，测试里有界多给点）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    const order = ['下载', '属性', '复制链接', '访问密码', '移动', '重命名', '修改简介', '删除'];
    expect(adaptiveSheetGroupLabels(tester, 0), ['下载', '属性', '复制链接']);
    expect(adaptiveSheetGroupLabels(tester, 1), [
      '访问密码',
      '移动',
      '重命名',
      '修改简介',
      '删除',
    ]);
    expect(
      find.byKey(const ValueKey('adaptive-m3e-menu-group-2')),
      findsNothing,
    );
    expect(adaptiveSheetTiles(), findsNWidgets(order.length));
    for (final label in order) {
      // 页面本身也有「删除」这类文案，断言限定在自适应动作面板里
      expect(adaptiveSheetAction(label), findsOneWidget, reason: label);
    }
    // 顺序：下载 / 属性 / 复制链接 / 访问密码 / 移动 / 重命名 / 修改简介 / 删除
    final tops = [
      for (final label in order)
        tester.getTopLeft(adaptiveSheetAction(label)).dy,
    ];
    for (int i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '「${order[i]}」要排在「${order[i - 1]}」下面',
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
        matching: find.byIcon(Icons.input_field),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
        matching: find.byIcon(Icons.description_outlined),
      ),
      findsOneWidget,
    );

    // 点「属性」→ 打开文件属性弹窗（那一行 5 个图标按钮）
    await tester.tap(adaptiveSheetAction('属性'));
    await settleSheet(tester);
    expect(sheetToggleButtons(), findsNWidgets(5));
    expect(sheetText('类型'), findsOneWidget);
    expect(sheetText('ZIP 文件'), findsOneWidget);
    expect(sheetText('重命名'), findsNothing);
    expect(sheetTooltip('更多操作'), findsOneWidget);
  });

  testWidgets('网盘页文件菜单：下载入队，重复下载提示跳过', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    final manager = buildTransferManagerForEnvironment(app.environment);
    await pumpDrive(tester, app, manager: manager);

    Future<void> openMenuAndTapDownload() async {
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(adaptiveSheetAction('下载'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await openMenuAndTapDownload();
    expect(client.shareFileCalls, 1);
    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single.refId, ':f1');
    expect(find.text('已开始下载'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await openMenuAndTapDownload();
    expect(client.shareFileCalls, 1);
    expect(manager.tasks, hasLength(1));
    expect(find.text('文件已在传输列表'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('网盘页文件 ⋯ 菜单：复制链接复制的是分享链接（带提取码）', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpDrive(tester, app);
    await tester.tap(find.byTooltip('文件操作'));
    // ⋯ 菜单是弹簧展开的：pump 到它长出来
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(adaptiveSheetAction('复制链接'));
    await tester.pumpAndSettle();

    // 和属性弹窗一样：现取分享信息，把链接（含提取码）写进剪贴板
    expect(client.shareFileCalls, 1);
    expect(clipboard, hasLength(1));
    final copied = '${(clipboard.single.arguments as Map)['text']}';
    expect(copied, contains(FakeDriveClient.fileUrl));
    expect(copied, contains('abcd'));
  });

  testWidgets('网盘单条目菜单使用 Riverpod 客户端', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(adaptiveSheetAction('复制链接'));
    await tester.pumpAndSettle();

    expect(client.shareFileCalls, 1);
    expect(clipboard, hasLength(1));

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    expect(client.shareFileCalls, 2);
    expect(toggleButton(tester, '复制链接').enabled, isTrue);
    await openPropertyMore(tester);
    await tester.tap(menuRowText('重命名'));
    await settleSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      'b.zip',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await settleSheet(tester);
    expect(sheetText('b.zip'), findsOneWidget);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('修改简介'));
    await settleSheet(tester);
    await tester.enterText(find.byType(TextField), '新简介');
    await tester.tap(find.text('确定'));
    await settleSheet(tester);

    expect(client.renamedFiles, ['b.zip']);
    expect(client.savedDescs, ['新简介']);

    // 等提示条消失后再打开，避免点击被遮挡。
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    Navigator.of(tester.element(find.byType(DrivePage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('文件操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(adaptiveSheetAction('删除'));
    await settleSheet(tester);
    expect(find.text('删除确认'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.deletedItems, [(id: 'f1', isFile: true)]);
  });

  testWidgets('网盘批量操作使用 Riverpod 客户端', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpDrive(tester, app);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('复制链接'));
    await tester.pumpAndSettle();

    expect(client.shareFileCalls, 1);
    expect(clipboard, hasLength(1));
    // 等复制提示条消失，避免它盖住底部多选操作栏。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除确认'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.deletedItems, [(id: 'f1', isFile: true)]);
  });

  testWidgets('网盘多选只有文件夹时“移动”置灰', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);

    await tester.longPress(find.text('子文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await settleSheet(tester);

    final row = tester.widget<ListTile>(find.widgetWithText(ListTile, '移动'));
    expect(row.enabled, isFalse);
  });

  testWidgets('网盘多选：操作栏顺序与批量重命名预览生效', (tester) async {
    final client = ManyFilesClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.longPress(find.text('file1.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('file2.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byTooltip('排序'));
    await settleSheet(tester);
    expect(
      find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
      findsOneWidget,
    );
    await tester.tap(find.text('名称'));
    await tester.pumpAndSettle();
    expect(find.text('时间'), findsNothing);
    expect(find.text('已选择 2 项'), findsOneWidget);

    final gridBefore = app.environment.cachePageSettings.store.gridView;
    await tester.tap(find.byTooltip('视图'));
    await settleSheet(tester);
    await tester.tap(find.text(gridBefore ? '列表视图' : '网格视图'));
    await tester.pumpAndSettle();
    expect(app.environment.cachePageSettings.store.gridView, !gridBefore);
    expect(find.text('已选择 2 项'), findsOneWidget);

    expect(
      tester
          .widgetList<BatchAction>(find.byType(BatchAction))
          .map((action) => action.label),
      ['下载', '复制链接', '收藏', '删除', '更多'],
    );

    await tester.tap(find.byTooltip('更多'));
    await settleSheet(tester);
    expect(
      find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
      findsOneWidget,
    );
    const moreOrder = ['访问密码', '移动', '重命名', '修改简介'];
    final moreTops = [
      for (final label in moreOrder)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(M3EBottomSheet),
                matching: find.text(label),
              ),
            )
            .dy,
    ];
    for (var i = 1; i < moreTops.length; i++) {
      expect(moreTops[i], greaterThan(moreTops[i - 1]), reason: moreOrder[i]);
    }

    await tester.tap(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.text('重命名'),
      ),
    );
    await settleSheet(tester);
    expect(
      find.byKey(const ValueKey('drive-batch-rename-supporting-text')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-search')),
      'file',
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-replacement')),
      'doc: ',
    );
    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-preview')));
    await settleSheet(tester);
    expect(find.text('file1.zip → doc: 1.zip'), findsOneWidget);
    expect(find.text('file2.zip → doc: 2.zip'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(client.renamedFiles, ['doc: 1.zip', 'doc: 2.zip']);
    expect(find.text('doc: 1.zip'), findsOneWidget);
    expect(find.text('doc: 2.zip'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('网盘批量重命名：文件失败时文件夹仍成功并汇总', (tester) async {
    final client = PartialBatchRenameClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app, freeTier: true);

    await tester.longPress(find.text('file1.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('file-folder'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await settleSheet(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(M3EBottomSheet),
        matching: find.text('重命名'),
      ),
    );
    await settleSheet(tester);
    expect(
      find.byKey(const ValueKey('drive-batch-rename-supporting-text')),
      findsOneWidget,
    );
    expect(find.text('修改文件名称需开通会员'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-search')),
      'file',
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-replacement')),
      'doc: ',
    );
    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-preview')));
    await settleSheet(tester);
    final invalidReplacement = tester.widget<TextField>(
      find.byKey(const ValueKey('drive-batch-rename-replacement')),
    );
    expect(invalidReplacement.decoration?.errorText, '包含非法字符');
    expect(find.text('file1.zip → doc: 1.zip'), findsNothing);
    expect(client.renamedFiles, isEmpty);
    expect(client.renamedFolders, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('drive-batch-rename-replacement')),
      'doc',
    );
    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-preview')));
    await settleSheet(tester);
    await tester.tap(find.byKey(const ValueKey('drive-batch-rename-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(client.renamedFolders, ['doc-folder']);
    expect(find.text('doc-folder'), findsOneWidget);
    expect(find.text('file1.zip'), findsOneWidget);
    expect(find.text('已重命名 1 个条目，1 个失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
