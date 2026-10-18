import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/dynamic_color_support.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 动态取色插件的通道：返回非空即表示设备支持动态取色。
const _dynamicColorChannel = MethodChannel('io.material.plugins/dynamic_color');

void mockDynamicColorSupport({required bool supported}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_dynamicColorChannel, (call) async {
        if (call.method == 'getCorePalette') {
          return supported
              ? Int32List.fromList(List<int>.filled(65, 0x2E6BE6))
              : null;
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_dynamicColorChannel, null),
  );
}

/// 打开某个设置大类页（设置拆成 5 页后，各用例只关心自己那一页）。
Future<AppController> pumpSettings(
  WidgetTester tester,
  SettingsCategory category,
) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppController();
  addTearDown(app.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      // 主题跟随设置（同真实外壳）：切深色模式要真的变主题，
      // 「纯黑深色主题」这类跟随亮度的设置项才测得到
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          themeMode: switch (app.settings.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: SettingsCategoryPage(category: category),
        ),
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

/// 滚动到某个设置项，再往回拖一点，让它避开浮层顶栏（可点）。
Future<void> scrollTo(WidgetTester tester, String text) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(find.text(text), 400, scrollable: scrollable);
  await tester.drag(scrollable, const Offset(0, 120));
  await tester.pumpAndSettle();
}

void main() {
  // 分组小节顺序：每个大类页里的小标题按设计顺序排列
  testWidgets('分组小节顺序：行为 → 无障碍 → 权限 / 备份 → 隐私 → 数据', (tester) async {
    await pumpSettings(tester, SettingsCategory.behaviorPermissions);
    expect(
      tester.getTopLeft(find.text('行为')).dy,
      lessThan(tester.getTopLeft(find.text('无障碍')).dy),
    );
    expect(
      tester.getTopLeft(find.text('无障碍')).dy,
      lessThan(tester.getTopLeft(find.text('权限')).dy),
    );

    await pumpSettings(tester, SettingsCategory.privacyData);
    expect(
      // 「备份与恢复」既是小标题也是条目名：取标题（树里在前）
      tester.getTopLeft(find.text('备份与恢复').first).dy,
      lessThan(tester.getTopLeft(find.text('隐私')).dy),
    );
    expect(
      tester.getTopLeft(find.text('隐私')).dy,
      lessThan(tester.getTopLeft(find.text('数据')).dy),
    );
  });

  testWidgets('设置项图标：管理权限=shield，清除数据=ink eraser', (tester) async {
    await pumpSettings(tester, SettingsCategory.behaviorPermissions);
    expect(iconOf(tester, '管理权限'), Icons.shield);

    await pumpSettings(tester, SettingsCategory.privacyData);
    expect(iconOf(tester, '清除数据'), Icons.ink_eraser);
  });

  // 高级覆盖项不再单占一组：入口行并进「连接」组最后一行
  testWidgets('高级覆盖项并入「连接」组最后一行，点开进二级页', (tester) async {
    await pumpSettings(tester, SettingsCategory.transferConnection);

    // 只剩入口行本身；原来的独立分组小标题（同名文案）没有了
    expect(find.text('高级覆盖项'), findsOneWidget);

    // 和「网络请求间隔」在同一个列表组里，且排在它下面（连接组最后一项）
    final group = find.ancestor(
      of: find.text('高级覆盖项'),
      matching: find.byType(SegmentedList),
    );
    expect(
      find.descendant(of: group, matching: find.text('网络请求间隔')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('高级覆盖项')).dy,
      greaterThan(tester.getTopLeft(find.text('网络请求间隔')).dy),
    );

    await scrollTo(tester, '高级覆盖项');
    await tester.tap(find.text('高级覆盖项'));
    await tester.pumpAndSettle();
    // 二级页（提示文案 + 三条覆盖项）
    expect(find.text('正常情况下不宜更改这些选项，否则可能导致相关功能故障'), findsOneWidget);
    expect(find.text('网盘接口域名'), findsOneWidget);
  });

  // 纯黑只对深色界面有意义：深色模式、或「跟随系统」且系统是深色时才出现
  testWidgets('纯黑深色主题：仅深色界面时显示', (tester) async {
    await pumpSettings(tester, SettingsCategory.appearanceLayout);
    // 默认跟随系统且系统浅色：隐藏
    expect(find.text('纯黑深色主题'), findsNothing);

    final themeGroup = find.byType(M3eConnectedButtonGroup<String>);
    // 切到深色：出现
    await tester.tap(
      find.descendant(of: themeGroup, matching: find.text('深色')).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('纯黑深色主题'), findsOneWidget);

    // 切回浅色：隐藏（即使系统是深色也不显示）
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.tap(
      find.descendant(of: themeGroup, matching: find.text('浅色')).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('纯黑深色主题'), findsNothing);

    // 跟随系统 + 系统深色：出现
    await tester.tap(
      find.descendant(of: themeGroup, matching: find.text('系统')).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('纯黑深色主题'), findsOneWidget);
  });

  // 主题色弹窗：第一项是动态取色（替代原来的独立开关），与颜色互斥
  testWidgets('主题色弹窗：第一项动态取色，选中/切色互相联动', (tester) async {
    mockDynamicColorSupport(supported: true);
    await DynamicColorSupport.isSupported(refresh: true);
    final app = await pumpSettings(tester, SettingsCategory.appearanceLayout);

    await scrollTo(tester, '主题色');
    await tester.tap(find.text('主题色'));
    await tester.pumpAndSettle();

    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    // 第一项：动态取色 + 副标题
    expect(inDialog('动态取色'), findsOneWidget);
    expect(inDialog('跟随系统壁纸取色'), findsOneWidget);
    expect(inDialog('默认蓝'), findsOneWidget);

    // 选中动态取色：落盘，行副标题变成「动态取色」，尾部不再画色块
    await tester.tap(inDialog('动态取色'));
    await tester.pumpAndSettle();
    expect(app.settings.dynamicColor, isTrue);
    expect(find.text('动态取色'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '主题色'),
        matching: find.byType(CircleAvatar),
      ),
      findsNothing,
    );

    // 改选具体颜色：关闭动态取色、seed 更新，色块回来
    await tester.tap(find.text('主题色'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('默认蓝'));
    await tester.pumpAndSettle();
    expect(app.settings.dynamicColor, isFalse);
    expect(app.settings.themeSeed, 0xFF2E6BE6);
    expect(find.text('默认蓝'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '主题色'),
        matching: find.byType(CircleAvatar),
      ),
      findsOneWidget,
    );
  });

  testWidgets('系统不支持动态取色：弹窗第一项置灰不可点', (tester) async {
    mockDynamicColorSupport(supported: false);
    await DynamicColorSupport.isSupported(refresh: true);
    final app = await pumpSettings(tester, SettingsCategory.appearanceLayout);

    await scrollTo(tester, '主题色');
    await tester.tap(find.text('主题色'));
    await tester.pumpAndSettle();

    expect(find.text('当前系统不支持动态取色'), findsOneWidget);
    // 置灰：点它没反应，弹窗还在、设置不变
    await tester.tap(find.text('动态取色'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(app.settings.dynamicColor, isFalse);
  });

  testWidgets('数据组底部是「清理缓存」，点击弹出确认弹窗（取消不清理）', (tester) async {
    await pumpSettings(tester, SettingsCategory.privacyData);

    final entry = find.text('清理缓存');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    // 它在「最近使用条数」下面：数据组最后一项
    expect(
      tester.getTopLeft(entry).dy,
      greaterThan(tester.getTopLeft(find.text('最近使用条数')).dy),
    );

    await tester.tap(entry);
    await tester.pump();
    // 先弹「加载中…」统计缓存大小（Windows 上这一步要几秒），统计完才弹确认框
    expect(find.text('加载中…'), findsOneWidget);
    // 统计缓存大小要走真实文件系统：给它一点时间再等弹窗
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(find.text('加载中…'), findsNothing);
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
    final app = await pumpSettings(tester, SettingsCategory.appearanceLayout);

    // 主题色在第一组（外观）里，初始就在屏幕内；不要再 ensureVisible，
    // 否则会被滚到顶部、缩到浮层顶栏下面点不到
    final entry = find.text('主题色');
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('经典紫'), findsOneWidget);
    expect(find.text('宝蓝'), findsOneWidget);
    expect(find.text('玫红'), findsOneWidget);
    expect(find.text('琥珀'), findsOneWidget);

    // 列表第一项是动态取色，预设颜色往下排：先滚到目标项再点
    // （弹窗内容会滚动，直接点会被挤到可视区外）
    await tester.ensureVisible(find.text('经典紫'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('经典紫'));
    await tester.pumpAndSettle();
    expect(app.settings.themeSeed, 0xFF6750A4);
  });

  // 下载目录弹窗：分类提示 + 使用说明只在 Android 显示
  testWidgets('下载目录弹窗：Android 显示提示文案', (tester) async {
    await pumpSettings(tester, SettingsCategory.transferConnection);
    final entry = find.text('下载目录');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    // ensureVisible 会把条目贴到浮层顶栏下面（点不到）：往回滚一点再点
    await tester.drag(find.byType(SettingsCategoryPage), const Offset(0, 240));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettingsCategoryPage)),
    );
    expect(find.text(l10n.downloadDirHint), findsOneWidget);
    // 当前目录按分类显示：默认即私有目录（只看弹窗里的那行）
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('私有目录（'),
      ),
      findsOneWidget,
    );

    // 点弹窗外关闭
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text(l10n.downloadDirHint), findsNothing);
  });

  testWidgets('下载目录弹窗：Windows 不显示提示文案', (tester) async {
    // 这个 debug 变量必须在用例体内复位（tearDown 里复位会被框架判定为
    // 「测试改了 foundation debug 变量」）
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpSettings(tester, SettingsCategory.transferConnection);
      final entry = find.text('下载目录');
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SettingsCategoryPage),
        const Offset(0, 240),
      );
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SettingsCategoryPage)),
      );
      expect(find.text(l10n.downloadDirHint), findsNothing);
      // 桌面端仍是「默认（路径）」的写法（只看弹窗里的那行）
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('默认（'),
        ),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // 什么都没勾就点「清除」：不装清空成功，明确提示未选择
  testWidgets('「清除数据」什么都不选点清除：提示未选择清除项', (tester) async {
    await pumpSettings(tester, SettingsCategory.privacyData);
    final entry = find.text('清除数据');
    // 直接滚到底：清除数据是隐私组的最后一项
    await tester.drag(
      find.byType(SettingsCategoryPage),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SettingsCategoryPage),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('未选择清除项'), findsOneWidget);
    expect(find.text('已清空'), findsNothing);

    // 让 SnackBar 自己走完生命周期，别留挂起的定时器
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('「清除数据」弹窗：两组分组小标题 + 复选列表，取消不清', (tester) async {
    final app = await pumpSettings(tester, SettingsCategory.privacyData);
    // 有登录账号才会显示「此账号」组
    app.accounts.accounts.add(Account(uid: '556911', cookie: 'c'));
    app.accounts.activeUid = '556911';
    app.notifyListeners();
    await tester.pumpAndSettle();

    final entry = find.text('清除数据');
    // 直接滚到底：清除数据是隐私组的最后一项
    await tester.drag(
      find.byType(SettingsCategoryPage),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SettingsCategoryPage),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    // 弹窗标题 + 两组分组小标题
    expect(find.text('清除数据'), findsNWidgets(2));
    expect(find.text('此账号'), findsOneWidget);
    expect(find.text('其他数据'), findsOneWidget);
    // 选项与说明
    expect(find.text('快速访问'), findsOneWidget);
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('其他账号数据'), findsOneWidget);
    expect(find.text('其他账号的相关数据，如快速访问、最近使用'), findsOneWidget);
    expect(find.text('运行日志'), findsOneWidget);
    // 注册表项目只有 Windows 端才有
    expect(find.text('注册表项目'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('清除'), findsOneWidget);

    Checkbox checkboxOf(String label) => tester.widget<Checkbox>(
      find.descendant(
        of: find.widgetWithText(ListTile, label),
        matching: find.byType(Checkbox),
      ),
    );

    // 默认全不勾；点一行只勾它自己
    expect(checkboxOf('运行日志').value, isFalse);
    await tester.tap(find.text('运行日志'));
    await tester.pumpAndSettle();
    expect(checkboxOf('运行日志').value, isTrue);
    expect(checkboxOf('快速访问').value, isFalse);

    // 取消：弹窗关掉，什么都不清
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('运行日志'), findsNothing);
  });

  testWidgets('「清除数据」弹窗：Windows 端多出注册表项目（含说明）', (tester) async {
    // 这个 debug 变量必须在用例体内复位（tearDown 里复位会被框架判定为
    // 「测试改了 foundation debug 变量」）
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpSettings(tester, SettingsCategory.privacyData);
      final entry = find.text('清除数据');
      // 直接滚到底：清除数据是隐私组的最后一项
      await tester.drag(
        find.byType(SettingsCategoryPage),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SettingsCategoryPage),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.text('注册表项目'), findsOneWidget);
      expect(find.text('为显示系统通知图标而创建的注册表项'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
