import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;

import 'support/drive_property_test_support.dart';

void main() {
  testWidgets('文件属性弹窗：快捷操作与详情分层，低频操作收进更多菜单', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);

    // 一行 5 个纯图标按钮：下载 / 复制链接 / 二维码 / 收藏 / 更多操作
    expect(sheetToggleButtons(), findsNWidgets(5));
    for (final tooltip in ['下载', '复制链接', '显示二维码', '添加收藏', '更多操作']) {
      expect(toggleButton(tester, tooltip), isNotNull, reason: tooltip);
    }

    // 详细信息按「标签在上、值在下」集中为一个列表组。
    expect(sheetText('类型'), findsOneWidget);
    expect(sheetText('ZIP 文件'), findsOneWidget);
    expect(sheetText('大小'), findsOneWidget);
    expect(sheetText('1.0 MB'), findsOneWidget);
    expect(sheetText('时间'), findsOneWidget);
    expect(sheetText('3 天前'), findsOneWidget);
    expect(sheetText('下载数'), findsOneWidget);
    expect(sheetText('3'), findsOneWidget);
    expect(sheetText('访问密码'), findsOneWidget);
    expect(sheetText('已启用'), findsOneWidget);

    // 低频动作不再直接铺在属性页里。
    expect(sheetText('重命名'), findsNothing);
    expect(sheetText('修改简介'), findsNothing);
    expect(sheetText('移动'), findsNothing);
    expect(sheetText('删除'), findsNothing);
    // 「打开链接」入口已删（提示条里的复制链接等照旧）
    expect(sheetText('打开链接'), findsNothing);

    // 更多菜单复用条目菜单，但去掉快捷按钮里已有的动作和“属性”自身。
    await openPropertyMore(tester);
    const moreOrder = ['访问密码', '移动', '重命名', '修改简介', '删除'];
    expect(find.byType(M3eMenuRow), findsNWidgets(moreOrder.length));
    for (final label in moreOrder) {
      expect(menuRowText(label), findsOneWidget, reason: label);
    }
    expect(menuRowText('属性'), findsNothing);
    expect(menuRowText('下载'), findsNothing);
    expect(menuRowText('复制链接'), findsNothing);
  });

  testWidgets('文件属性弹窗：移动取消保留弹窗，确认成功后再关闭', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('移动'));
    await settleSheet(tester);
    expect(find.text('选择目标文件夹'), findsOneWidget);
    expect(find.byType(M3EBottomSheet), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await settleSheet(tester);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(client.movedFiles, isEmpty);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('移动'));
    await settleSheet(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final moveHere = find.widgetWithText(FilledButton, '移动到此');
    expect(tester.widget<FilledButton>(moveHere).onPressed, isNotNull);
    await tester.tap(moveHere);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(client.movedFiles, [(id: 'f1', folderId: '-1')]);
    expect(find.byType(M3EBottomSheet), findsNothing);
  });

  testWidgets('文件属性弹窗：删除取消保留弹窗，确认成功后再关闭', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('删除'));
    await settleSheet(tester);
    expect(find.text('删除确认'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await settleSheet(tester);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(client.deletedItems, isEmpty);

    await openPropertyMore(tester);
    await tester.tap(menuRowText('删除'));
    await settleSheet(tester);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(client.deletedItems, [(id: 'f1', isFile: true)]);
    expect(find.byType(M3EBottomSheet), findsNothing);
  });

  testWidgets('文件属性弹窗：复制链接弹出 MD3E 菜单（分享链接 / 下载直链）', (tester) async {
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
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    await tester.tap(sheetTooltip('复制链接'));
    await settleSheet(tester);
    // 菜单是弹簧展开的：等它长出来再断言（真机上就是一两帧的事）
    await tester.pumpAndSettle();

    // 菜单是贴在被点那一段下面的弹出菜单：属性弹窗还在，菜单浮在它上面
    expect(sheetToggleButtons(), findsNWidgets(5));
    expect(find.byType(M3eMenuRow), findsNWidgets(2));
    expect(find.text('复制分享链接'), findsOneWidget);
    expect(find.text('复制下载直链'), findsOneWidget);

    // 菜单左缘跟着被点的那一段（而不是整个按钮组），并且贴着它的下边缘
    final Rect button = tester.getRect(sheetTooltip('复制链接'));
    final Rect item = tester.getRect(find.byType(M3eMenuRow).first);
    expect(
      (item.left - button.left).abs(),
      lessThan(24),
      reason: '菜单左缘要对准被点的那一段',
    );
    expect(item.top, greaterThan(button.bottom), reason: '菜单要贴在那一段下方');

    await tester.tap(find.text('复制下载直链'));
    await settleSheet(tester);
    expect(clipboard, hasLength(1));
    expect(
      '${(clipboard.single.arguments as Map)['text']}',
      'https://cdn.example/a.zip',
    );
  });

  testWidgets('文件属性弹窗：收藏态没加载出来前，收藏按钮置灰', (tester) async {
    final client = GatedDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);

    // 分享信息（收藏判定要用它的链接）还没回来：收藏按钮不可点，
    // 否则会在状态未知时点出「重复收藏 / 错误取消收藏」
    expect(toggleButton(tester, '添加收藏').enabled, isFalse);
    // 下载 / 复制链接 / 二维码都复用这份分享信息，等它回来再放开
    expect(toggleButton(tester, '下载').enabled, isFalse);
    expect(toggleButton(tester, '复制链接').enabled, isFalse);
    expect(toggleButton(tester, '显示二维码').enabled, isFalse);
    // 更多菜单使用列表里的数据，不依赖这次分享请求。
    expect(toggleButton(tester, '更多操作').enabled, isTrue);
  });

  testWidgets('文件属性弹窗：下载 / 复制链接 / 二维码复用弹窗取回的分享信息', (tester) async {
    final client = FakeDriveClient();
    final app = FakeDriveApp(client);
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    // 打开弹窗时取过一次（收藏判定）
    expect(client.shareFileCalls, 1);

    // 弹菜单、选「复制分享链接」都不再请求分享信息
    await tester.tap(sheetTooltip('复制链接'));
    await tester.pumpAndSettle();
    expect(client.shareFileCalls, 1);
    await tester.tap(find.text('复制分享链接'));
    await settleSheet(tester);
    expect(client.shareFileCalls, 1);
    // 复制完属性弹窗还在（反馈走浮在最上层的轻提示）
    expect(sheetToggleButtons(), findsNWidgets(5));
  });

  testWidgets('文件属性弹窗：收藏就地切换，不关弹窗', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);

    await tester.tap(find.text('a.zip'));
    await settleSheet(tester);
    await tester.tap(find.byTooltip('添加收藏'));
    await settleSheet(tester);

    // 测试环境没有 sqflite：收藏会失败并回滚，但弹窗必须还在
    expect(sheetToggleButtons(), findsNWidgets(5));
    expect(toggleButton(tester, '添加收藏').checked, isFalse);
  });
}
