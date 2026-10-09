import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

Future<AppController> pumpSettings(WidgetTester tester) async {
  final app = AppController();
  addTearDown(app.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// 某个设置项前面的图标。
IconData iconOf(WidgetTester tester, String title) {
  return tester
      .widget<Icon>(
        find.descendant(
          of: find.widgetWithText(ListTile, title),
          matching: find.byType(Icon),
        ),
      )
      .icon!;
}

void main() {
  // 权限组使用频率低：整组排在隐私组之后（分组顺序与条目声明顺序无关）
  testWidgets('「权限」分组排在「隐私」分组之后', (tester) async {
    await pumpSettings(tester);
    final privacy = tester.getTopLeft(find.text('隐私'));
    final permissions = tester.getTopLeft(find.text('权限'));
    expect(privacy.dy, lessThan(permissions.dy));
  });

  testWidgets('设置项图标：管理权限=shield，清空最近使用记录=delete sweep', (tester) async {
    await pumpSettings(tester);
    expect(iconOf(tester, '管理权限'), Icons.shield);
    expect(iconOf(tester, '清空最近使用记录'), Icons.delete_sweep_outlined);
  });

  testWidgets('数据组底部是「清理缓存」，点击弹出确认弹窗（取消不清理）', (tester) async {
    await pumpSettings(tester);

    final entry = find.text('清理缓存');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    // 它在「清空最近使用记录」下面：数据组最后一项
    expect(
      tester.getTopLeft(entry).dy,
      greaterThan(tester.getTopLeft(find.text('清空最近使用记录')).dy),
    );

    await tester.tap(entry);
    await tester.pump();
    // 统计缓存大小要走真实文件系统：给它一点时间再等弹窗
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    // 弹窗：标题 + 取消 / 清理 两个按钮
    expect(find.text('清理缓存'), findsNWidgets(2));
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('清理'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('清理'), findsNothing);
  });

  // MD3 基准色等新增预设：主题色弹窗里能选到，并能写入设置
  testWidgets('主题色新增预设可选（经典紫 / 宝蓝 / 玫红 / 琥珀）', (tester) async {
    final app = await pumpSettings(tester);

    // 主题色在第一组（外观）里，初始就在屏幕内；不要再 ensureVisible，
    // 否则会被滚到顶部、缩到浮层顶栏下面点不到
    final entry = find.text('主题色');
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('经典紫'), findsOneWidget);
    expect(find.text('宝蓝'), findsOneWidget);
    expect(find.text('玫红'), findsOneWidget);
    expect(find.text('琥珀'), findsOneWidget);

    await tester.tap(find.text('经典紫'));
    await tester.pumpAndSettle();
    expect(app.settings.themeSeed, 0xFF6750A4);
  });
}
