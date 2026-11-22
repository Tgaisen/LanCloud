import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;

import 'support/drive_property_test_support.dart';

void main() {
  testWidgets('网盘页文件夹 ⋯ 菜单：重命名与简介拆分，属性打开属性弹窗', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.byTooltip('文件夹操作'));
    // ⋯ 菜单是弹簧展开的：pump 到它长出来
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // 文件夹菜单：打开 / 属性 / 快速访问 / 复制链接 / 访问密码 / 重命名 / 修改简介 / 删除
    //（「打开」排第一，与点文件夹卡片等效；文件夹没有「移动」）
    const order = ['打开', '属性', '添加到快速访问', '复制链接', '访问密码', '重命名', '修改简介', '删除'];
    expect(adaptiveSheetGroupLabels(tester, 0), [
      '打开',
      '属性',
      '添加到快速访问',
      '复制链接',
    ]);
    expect(adaptiveSheetGroupLabels(tester, 1), ['访问密码', '重命名', '修改简介', '删除']);
    expect(
      find.byKey(const ValueKey('adaptive-m3e-menu-group-2')),
      findsNothing,
    );
    expect(adaptiveSheetTiles(), findsNWidgets(order.length));
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

    // 点「属性」→ 打开文件夹属性弹窗
    await tester.tap(adaptiveSheetAction('属性'));
    await settleSheet(tester);
    // 菜单 → 弹窗比原来多一次路由（先收菜单再开弹窗）：多给一帧，
    // 让弹窗里的分享信息和统计请求跑完。
    await tester.pump(const Duration(milliseconds: 200));

    expect(sheetToggleButtons(), findsNWidgets(5));
    for (final tooltip in ['复制链接', '显示二维码', '添加收藏', '添加到快速访问', '更多操作']) {
      expect(toggleButton(tester, tooltip), isNotNull, reason: tooltip);
    }
    // 测试环境没有 sqflite：读不到「是否已固定」，固定按钮保持置灰
    // （真机上库可用，读回来即恢复可点）
    expect(toggleButton(tester, '添加到快速访问').enabled, isFalse);

    // 文件夹没有时间行，只展示类型、大小、文件数和密码状态。
    expect(sheetText('类型'), findsOneWidget);
    expect(sheetText('文件夹'), findsOneWidget);
    expect(sheetText('大小'), findsOneWidget);
    expect(sheetText('2.0 MB'), findsOneWidget);
    expect(sheetText('文件数'), findsOneWidget);
    expect(sheetText('7'), findsOneWidget);
    expect(sheetText('访问密码'), findsOneWidget);
    expect(sheetText('已启用'), findsOneWidget);
    expect(sheetText('时间'), findsNothing);

    // 低频操作收进更多菜单，不再直接铺在属性页里。
    expect(sheetText('重命名'), findsNothing);
    expect(sheetText('修改简介'), findsNothing);
    expect(sheetText('打开'), findsNothing);
    // 名称与简介是两个独立入口，不再带合并操作的副标题
    expect(sheetText('修改名称与简介'), findsNothing);
    // 「打开链接」入口已删
    expect(sheetText('打开链接'), findsNothing);
    expect(sheetText('删除'), findsNothing);

    await openPropertyMore(tester);
    const moreOrder = ['访问密码', '重命名', '修改简介', '删除'];
    expect(find.byType(M3eMenuRow), findsNWidgets(moreOrder.length));
    for (final label in moreOrder) {
      expect(menuRowText(label), findsOneWidget, reason: label);
    }
    expect(menuRowText('属性'), findsNothing);
    expect(menuRowText('打开'), findsNothing);
    expect(menuRowText('复制链接'), findsNothing);
    expect(menuRowText('移动'), findsNothing);

    // 取消删除时文件夹属性页继续保留；确认动作由删除流程自己处理。
    await tester.tap(menuRowText('删除'));
    await settleSheet(tester);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await settleSheet(tester);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(client.deletedItems, isEmpty);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('重命名'));
    await settleSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      '新 文件夹',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await settleSheet(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('drive-rename-field')))
          .decoration
          ?.errorText,
      '包含非法字符',
    );
    expect(client.renamedFolders, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      '新文件夹',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await settleSheet(tester);
    expect(client.renamedFolders, ['新文件夹']);
    expect(sheetText('新文件夹'), findsOneWidget);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('修改简介'));
    await settleSheet(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '文件夹简介',
    );
    await tester.enterText(find.byType(TextField), '新文件夹简介');
    await tester.tap(find.text('确定'));
    await settleSheet(tester);
    expect(client.savedFolderDescs, ['新文件夹简介']);

    // 复制链接复用打开弹窗时取回的分享信息（不再请求一次）；
    // 注意这一步会把弹窗收起来，所以放在弹窗内容断言之后。
    expect(client.shareFolderCalls, 1);
    await tester.tap(sheetTooltip('复制链接'));
    await settleSheet(tester);
    expect(client.shareFolderCalls, 1);
  });

  testWidgets('文件属性弹窗：重命名与修改简介分别保存', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    await openPropertyMore(tester);
    await tester.tap(menuRowText('重命名'));
    await settleSheet(tester);

    // 只有名称输入框，预填当前名称
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('drive-rename-field')))
          .controller
          ?.text,
      'a.zip',
    );
    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      'b.zip',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await settleSheet(tester);

    expect(client.renamedFiles, ['b.zip']);
    expect(client.savedDescs, isEmpty);
    expect(sheetText('b.zip'), findsOneWidget);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('修改简介'));
    await settleSheet(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '文件简介',
    );
    await tester.enterText(find.byType(TextField), '新简介');
    await tester.tap(find.text('确定'));
    await settleSheet(tester);

    expect(client.savedDescs, ['新简介']);
    expect(sheetText('b.zip'), findsOneWidget);

    // 让提示条走完（否则测试结束时还挂着它的定时器）
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('文件属性弹窗：非会员重命名失败提示跟随英文界面', (tester) async {
    final app = FakeDriveApp(MemberRenameClient());
    const locale = Locale('en');
    final l10n = lookupAppLocalizations(locale);
    await pumpDrive(tester, app, locale: locale, freeTier: true);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    await openPropertyMore(tester, label: l10n.moreActions);
    await tester.tap(menuRowText(l10n.rename));
    await settleSheet(tester);

    expect(
      find.byKey(const ValueKey('drive-rename-supporting-text')),
      findsOneWidget,
    );
    expect(find.text(l10n.fileRenameMembershipHint), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('drive-rename-field')),
    );
    expect(field.decoration?.helperText, isNull);
    await tester.enterText(find.byType(TextField).first, 'b.zip');
    await tester.tap(find.text(l10n.modify));
    await settleSheet(tester);

    expect(find.text(l10n.lanzouRenameRequiresMembership), findsOneWidget);
    expect(find.text('重命名失败：此功能需要开通会员'), findsNothing);
  });

  testWidgets('文件属性弹窗：重命名名称为空时原地标错，弹窗不关也不发请求', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    await openPropertyMore(tester);
    await tester.tap(menuRowText('重命名'));
    await settleSheet(tester);

    // 清空名称后确定：MD3E error state（错误文本 + 尾部 fill 风格 Error 图标）
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('修改'));
    await settleSheet(tester);
    expect(find.text('请输入名称'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    // 弹窗还在，重命名接口没有被调用
    expect(find.byType(TextField), findsOneWidget);
    expect(client.renamedFiles, isEmpty);
    expect(client.savedDescs, isEmpty);

    // 补上名字就能正常保存
    await tester.enterText(find.byType(TextField).first, 'b.zip');
    await tester.tap(find.text('修改'));
    await settleSheet(tester);
    expect(client.renamedFiles, ['b.zip']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('文件重命名拒绝文件非法字符并允许文件专属字符', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    await openPropertyMore(tester);
    await tester.tap(menuRowText('重命名'));
    await settleSheet(tester);

    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      'bad/name.zip',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await settleSheet(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('drive-rename-field')))
          .decoration
          ?.errorText,
      '包含非法字符',
    );
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(client.renamedFiles, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('drive-rename-field')),
      'good:*?| name.zip',
    );
    await tester.tap(find.byKey(const ValueKey('drive-rename-confirm')));
    await settleSheet(tester);
    expect(client.renamedFiles, ['good:*?| name.zip']);
    expect(sheetText('good:*?| name.zip'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('文件夹属性弹窗：从网盘页「目录属性」进来不显示「打开」', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    // 站在子目录里：顶栏菜单才会出现「目录属性」
    await pumpDrive(tester, app, folderId: 'fd1', folderName: '子文件夹');

    await tester.tap(find.byTooltip('菜单'));
    await settleSheet(tester);
    expect(
      find.byKey(const ValueKey('adaptive-m3e-menu-sheet')),
      findsOneWidget,
    );
    expect(find.text('刷新'), findsOneWidget);
    expect(find.text('添加到快速访问'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('刷新')).dy,
      lessThan(tester.getTopLeft(find.text('添加到快速访问')).dy),
    );
    expect(
      tester.getTopLeft(find.text('添加到快速访问')).dy,
      lessThan(tester.getTopLeft(find.text('目录属性')).dy),
    );
    await tester.tap(find.text('目录属性'));
    await settleSheet(tester);

    expect(sheetTooltip('更多操作'), findsOneWidget);
    expect(sheetText('重命名'), findsNothing);
    expect(sheetText('修改简介'), findsNothing);
    expect(sheetText('打开'), findsNothing);

    await openPropertyMore(tester);
    expect(menuRowText('打开'), findsNothing);
    expect(menuRowText('属性'), findsNothing);
    expect(menuRowText('添加到快速访问'), findsNothing);
  });

  testWidgets('文件夹统计失败时直接显示未知，不再遍历全部分页', (tester) async {
    final app = FakeDriveApp(NoStatsClient());
    await pumpDrive(tester, app, folderId: 'fd1', folderName: '子文件夹');

    await tester.tap(find.byTooltip('菜单'));
    await settleSheet(tester);
    await tester.tap(find.text('目录属性'));
    await settleSheet(tester);

    expect(find.text('未知'), findsNWidgets(2));
    expect(find.text('2.0 MB'), findsNothing);
    expect(find.text('7'), findsNothing);
  });

  testWidgets('弹窗里的列表组：容器色比弹窗底高一档、窗体边距 16dp', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);

    void expectSheetList() {
      final list = tester.widget<SegmentedList>(
        find
            .descendant(
              of: find.byType(SheetListGroup),
              matching: find.byType(SegmentedList),
            )
            .first,
      );
      final scheme = Theme.of(tester.element(find.byType(SheetListGroup)))
          .colorScheme;
      // 比弹窗底（surfaceContainerLow）高一档
      expect(list.color, scheme.surfaceContainer);
      // 作为弹窗内容最后一块：底边与左右同值（16dp），是三边 16dp 的窗体边距
      expect(list.margin, SheetListGroup.endMargin);
    }

    // 文件属性弹窗
    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    expectSheetList();
    await tester.tapAt(const Offset(10, 10));
    await settleSheet(tester);

    // 「添加」弹窗
    await tester.tap(find.text('添加'));
    await settleSheet(tester);
    expectSheetList();
  });
}
