import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/profile_page_test_support.dart';

void main() {
  testWidgets('两栏无障碍：切类别后焦点进右窗格，顶栏标题是 liveRegion', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTwoPane(tester);

    // 初始：右窗格是账号管理，顶栏标题是 live region
    expect(paneTitleSemantics(tester, '账号管理').label, '账号管理');
    expect(
      paneTitleSemantics(tester, '账号管理').flagsCollection.isLiveRegion,
      isTrue,
    );

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();

    expect(focusedPaneLabel(), 'profile-detail-pane');
    // 类别切换后标题换成类别名（与单栏态 push 出来的类别页标题一致）
    expect(paneTitleSemantics(tester, '传输与连接').label, '传输与连接');
    expect(
      paneTitleSemantics(tester, '传输与连接').flagsCollection.isLiveRegion,
      isTrue,
    );
    // 语义句柄要在测试体内销毁：框架在 tearDown 之前就会校验
    semantics.dispose();
  });

  testWidgets('两栏无障碍：进二级页 / 返回后焦点进右窗格，标题 liveRegion 跟随', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTwoPane(tester);

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();

    // 进二级页：焦点回右窗格（新内容），标题换成二级页名
    final advancedTile = find.widgetWithText(ListTile, '高级覆盖项');
    await tester.ensureVisible(advancedTile);
    await tester.pumpAndSettle();
    await tester.tap(advancedTile);
    await tester.pumpAndSettle();
    expect(focusedPaneLabel(), 'profile-detail-pane');
    expect(paneTitleSemantics(tester, '高级覆盖项').label, '高级覆盖项');

    // 返回：回到类别层，同样把焦点带回右窗格，标题换回类别名
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(focusedPaneLabel(), 'profile-detail-pane');
    expect(paneTitleSemantics(tester, '传输与连接').label, '传输与连接');
    semantics.dispose();
  });

  testWidgets('两栏无障碍：左窗格 ↑ / ↓ 在条目之间移动焦点', (tester) async {
    await pumpTwoPane(tester);

    // Tab 落到左窗格第一条
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final first = FocusManager.instance.primaryFocus;
    expect(first, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(same(first)));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(first));
  });

  testWidgets('两栏无障碍：Esc 与返回等价（关二级页、退出搜索）', (tester) async {
    await pumpTwoPane(tester);

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();
    final advancedTile = find.widgetWithText(ListTile, '高级覆盖项');
    await tester.ensureVisible(advancedTile);
    await tester.pumpAndSettle();
    await tester.tap(advancedTile);
    await tester.pumpAndSettle();
    Finder appBarTitle(String text) =>
        find.descendant(of: find.byType(AppBar), matching: find.text(text));
    expect(appBarTitle('高级覆盖项'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(appBarTitle('传输与连接'), findsOneWidget);
    expect(find.text('网络请求间隔'), findsOneWidget);

    // 再按一次：搜索态下 Esc 退出搜索（这里先进入搜索）
    await tester.tap(find.byTooltip('搜索设置项'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
