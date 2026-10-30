import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_info.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/about_page.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

Widget host(AppController app, Widget home) => ProviderScope(
  overrides: [
    navigationAppearanceSettingsStateProvider.overrideWithValue(
      app.navigationAppearanceSettings,
    ),
    navigationStateProvider.overrideWithValue(app.navigation),
  ],
  child: MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: home,
  ),
);

void main() {
  testWidgets('关于页显示版本、协议入口与免责声明', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      host(app, const AboutPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝云'), findsOneWidget);
    // 中文文案已精简为「0.8.9 (56)」形式（与开源许可页里的版本号一致）
    expect(find.text('$appVersion ($appBuild)'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.text('项目主页'), findsOneWidget);
    expect(find.text('提交 Issue'), findsOneWidget);

    // 顶部主视觉与「开始使用」页共用同一套 MD3E 图标框和间距。
    final heroIcon = tester.widget<M3eShapedIcon>(find.byType(M3eShapedIcon));
    expect(heroIcon.icon, app_icons.Icons.info_outline);
    expect(heroIcon.size, 88);
    expect(heroIcon.iconSize, 44);
    expect(heroIcon.shape, Shapes.c4SidedCookie);
    expect(find.byType(Image), findsNothing);

    final iconRect = tester.getRect(find.byType(M3eShapedIcon));
    final titleRect = tester.getRect(find.text('蓝云'));
    final versionRect = tester.getRect(find.text('$appVersion ($appBuild)'));
    expect(titleRect.top - iconRect.bottom, 20);
    expect(versionRect.top - titleRect.bottom, 12);
    expect(titleRect.center.dx, moreOrLessEquals(versionRect.center.dx));

    // 「相关信息」用 Mobile Info，避免与顶部 Info 主视觉重复。
    final relatedTile = tester.widget<ListTile>(
      find
          .ancestor(of: find.text('相关信息'), matching: find.byType(ListTile))
          .first,
    );
    expect((relatedTile.leading! as Icon).icon, app_icons.Icons.mobile_info);

    // 弹窗类条目（不跳新页面）右侧不带箭头
    for (final label in ['用户协议', '隐私政策', '相关信息']) {
      final tile = tester.widget<ListTile>(
        find
            .ancestor(of: find.text(label), matching: find.byType(ListTile))
            .first,
      );
      expect(tile.trailing, isNull, reason: label);
    }
    // 用 TopBarOverlayScaffold 的页面都带快速滑动条
    expect(find.byType(FastScrollbar), findsOneWidget);
    app.dispose();
  });

  testWidgets('关于页可以打开隐私政策弹窗', (tester) async {
    final app = AppController();
    await tester.pumpWidget(
      host(app, const AboutPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('WebDAV'), findsWidgets);
    app.dispose();
  });

  testWidgets('关于页：提交 Issue 与相关信息同组；相关信息弹窗展示构建与设备信息', (tester) async {
    const channel = MethodChannel('lancloud/system');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'deviceInfo') return null;
          return {
            'manufacturer': 'HUAWEI',
            'model': 'NOH-AN00',
            'release': '12',
            'sdkInt': 31,
            'display': 'NOH-AN00 4.2.0.196(C00E182R8P6)',
            'abis': ['arm64-v8a', 'armeabi-v7a', 'armeabi'],
            'versionCode': 260107210,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final app = AppController();
    await tester.pumpWidget(
      host(app, const AboutPage()),
    );
    await tester.pumpAndSettle();

    // 构建信息已搬到更新页：关于页不再有入口
    expect(find.text('构建信息'), findsNothing);
    // 提交 Issue 单独一组，和相关信息同一列表组
    final group = find.ancestor(
      of: find.text('提交 Issue'),
      matching: find.byType(SegmentedList),
    );
    expect(
      find.descendant(of: group.first, matching: find.text('相关信息')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('相关信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相关信息'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(text, contains('App version: $appVersion'));
    expect(text, contains('Build: $appBuild (pre-release)'));
    expect(text, contains('Version code: 260107210'));
    // 本地测试构建没有注入构建时间 / 提交号：显示占位符
    expect(text, contains('Build time: —'));
    expect(text, contains('Commit: —'));
    expect(text, contains('Device: HUAWEI NOH-AN00'));
    expect(text, contains('System: Android 12 (31)'));
    expect(text, contains('System build: NOH-AN00 4.2.0.196(C00E182R8P6)'));
    expect(text, contains('Architecture: arm64-v8a, armeabi-v7a, armeabi'));
    app.dispose();
  });
}
