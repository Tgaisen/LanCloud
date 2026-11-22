import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/legal_dialog.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;

import 'support/drive_property_test_support.dart';

void main() {
  testWidgets('宽屏：新建文件夹弹窗宽度固定，不超过 M3 上限 560', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    // 宽屏（横屏 / 桌面）：以前弹窗会跟着输入内容一路变宽
    await pumpDrive(tester, app, viewSize: const Size(1200, 700));

    await tester.tap(find.text('添加'));
    await settleSheet(tester);
    expect(find.byKey(const ValueKey('m3e-menu-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-m3e-menu-sheet')), findsNothing);
    await tester.tap(find.text('新建文件夹'));
    await settleSheet(tester);
    // 自动聚焦 → 帧后量位置 → 180ms 上移动画：多给几帧让它走完
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(AlertDialog), findsOneWidget);
    // 页面顶栏还有搜索框，这里只看弹窗里的那个
    final Finder field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    // 新建文件夹弹窗带「名称 + 简介」两个输入框
    expect(field, findsNWidgets(2));
    // AlertDialog 的 RenderObject 是外层全屏 padding，量对话框本体要看内容的
    // 最近 Material 祖先（弹窗卡片）
    final Finder dialogCard = find
        .ancestor(of: field.first, matching: find.byType(Material))
        .first;
    final double width = tester.getSize(dialogCard).width;
    expect(width, lessThanOrEqualTo(560), reason: 'M3 弹窗上限 560dp');
    expect(width, greaterThan(400), reason: '宽屏下应贴近上限，而不是按内容缩着');

    // 输入很长的名字：宽度不该抽动（TextField 的固有宽度会随文本变）
    await tester.enterText(field.first, '这是一个很长很长的文件夹名字用来验证弹窗宽度不会抽动');
    await tester.pump();
    expect(tester.getSize(dialogCard).width, width);
  });

  testWidgets('横屏 + 输入法：新建文件夹弹窗里的输入框仍在弹窗内可见', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    // 横屏手机真实尺寸：792×368（NOH-AN00），微信输入法实测占 251dp →
    // 可用高度只剩 117dp，装不下「输入框 56 + 操作行 72」
    await pumpDrive(tester, app, viewSize: const Size(792, 368));
    tester.view.viewInsets = const FakeViewPadding(bottom: 251);
    addTearDown(tester.view.reset);

    await tester.tap(find.text('添加'));
    await settleSheet(tester);
    await tester.tap(find.text('新建文件夹'));
    await settleSheet(tester);

    // 自动聚焦 → 帧后量位置 → 180ms 上移动画：多给几帧让它走完
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // 紧凑形态下不再是 AlertDialog（内容和操作在同一个滚动区里），
    // 页面本身没有输入框，直接按类型找即可
    final Finder field = find.byType(TextField);
    expect(field, findsNWidgets(2), reason: '名称 + 简介两个输入框');
    final Finder card = find
        .ancestor(of: field.first, matching: find.byType(Material))
        .first;
    final Rect cardRect = tester.getRect(card);
    final Rect fieldRect = tester.getRect(field.first);

    expect(cardRect.height, greaterThan(0), reason: '弹窗本体不能被压没');
    expect(fieldRect.height, greaterThan(0), reason: '输入框要有高度');
    expect(
      cardRect.contains(fieldRect.center),
      isTrue,
      reason: '输入框不能被挤出弹窗（以前会被挤到看不见）',
    );
    expect(
      fieldRect.bottom,
      lessThanOrEqualTo(368 - 251 + 0.5),
      reason: '输入框要在输入法上方可见',
    );
  });

  testWidgets('竖屏 + 输入法：弹窗上移到剩余区域中间', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    // 竖屏手机：393×852，输入法占 300dp → 剩余区域高 552dp，弹窗放得下
    await pumpDrive(tester, app, viewSize: const Size(393, 852));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);

    await tester.tap(find.text('添加'));
    await settleSheet(tester);
    await tester.tap(find.text('新建文件夹'));
    await settleSheet(tester);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final Finder field = find.byType(TextField);
    final Finder card = find
        .ancestor(of: field.first, matching: find.byType(Material))
        .first;
    final Rect cardRect = tester.getRect(card);
    // 自然居中位置（852/2）上移半个键盘高度（150）→ 落在剩余区域 (0..552) 中心
    expect(
      cardRect.center.dy,
      closeTo((852 - 300) / 2, 1),
      reason: '弹窗应在输入法上方的剩余区域里居中',
    );
  });

  testWidgets('底部弹窗：键盘弹出时面板高度不缩（底部安全区按 viewPadding 稳定）', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app, viewSize: const Size(393, 852));
    // 系统导航栏 39dp：无键盘时 padding / viewPadding 都是 39
    tester.view.viewPadding = const FakeViewPadding(bottom: 39);
    tester.view.padding = const FakeViewPadding(bottom: 39);
    addTearDown(tester.view.reset);

    await tester.tap(find.text('添加'));
    await settleSheet(tester);
    final double withoutKeyboard = tester
        .getSize(find.byType(M3EBottomSheet))
        .height;

    // 键盘弹出：padding.bottom 归零（导航栏被输入法盖住），viewInsets 顶上
    tester.view.padding = const FakeViewPadding();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.getSize(find.byType(M3EBottomSheet)).height,
      withoutKeyboard,
      reason: '键盘弹出时底部弹窗不应矮一截（切换账号 → Cookie 登录弹窗那个 bug）',
    );
  });

  testWidgets('宽屏：用户协议弹窗宽度也被 560 夹住', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app, viewSize: const Size(1200, 700));

    // 与应用里一样，从页面 context 打开协议弹窗
    unawaited(
      showLegalDialog(tester.element(find.byType(DrivePage)), LegalDoc.privacy),
    );
    await tester.pumpAndSettle();

    final closeButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '关闭'),
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(of: closeButton, matching: find.byType(Material))
                .first,
          )
          .width,
      lessThanOrEqualTo(560),
    );
  });

  testWidgets('桌面端紧凑密度：菜单首尾贴近卡片内边距', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    PointerSupport.hasMouse.value = true;
    try {
      final app = FakeDriveApp(FakeDriveClient());
      // Windows 桌面默认 visualDensity.compact：行高被压到 40dp 而不是 48dp。
      // 卡片高度如果按 48dp 硬算，完全展开时底部就会多出一截空白。
      await pumpDrive(tester, app, density: VisualDensity.compact);

      await tester.tap(find.byTooltip('文件操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      final menuCard = find.byKey(const ValueKey('m3e-menu-card'));
      final Rect card = tester.getRect(menuCard);
      final rows = find.byType(M3eMenuRow);
      final Rect first = tester.getRect(rows.first);
      expect(first.height, 40, reason: '紧凑密度下 MenuItemButton 行高 40dp');
      expect(first.top - card.top, 4, reason: '首项到卡片顶边也是 4dp');

      await tester.drag(menuCard, const Offset(0, -400));
      await tester.pumpAndSettle();
      final Rect last = tester.getRect(find.byType(M3eMenuRow).last);
      expect(last.height, 40, reason: '滚动后末项仍保持紧凑行高');
      expect(card.bottom - last.bottom, 4, reason: '末项到卡片底边也是 4dp');
    } finally {
      PointerSupport.hasMouse.value = false;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
