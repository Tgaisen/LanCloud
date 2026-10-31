import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/account_session.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:lancloud/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

Future<AppController> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(420, 900),
}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppController();
  addTearDown(app.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(app.settings),
        accountStateProvider.overrideWithValue(app.accountState),
        accountSessionProvider.overrideWithValue(app.accountSession),
        appDbProvider.overrideWithValue(app.db),
        driveStateProvider.overrideWithValue(app.drive),
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
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('设置搜索：本页命中在前；其他设置项点击后替换当前页', (tester) async {
    await _pump(
      tester,
      const SettingsCategoryPage(category: SettingsCategory.appearanceLayout),
    );

    await tester.tap(find.byTooltip('搜索设置项'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '主题');
    await tester.pumpAndSettle();

    // 本页命中：主题模式 / 主题色都是本页条目，不出现「其他设置项」
    expect(find.text('其他设置项'), findsNothing);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('主题色'), findsOneWidget);

    // 换成别的类别才有的关键词：进入「其他设置项」
    await tester.enterText(find.byType(TextField), '下载目录');
    await tester.pumpAndSettle();
    expect(find.text('其他设置项'), findsOneWidget);
    final other = find.widgetWithText(ListTile, '下载目录');
    expect(other, findsOneWidget);
    // 行上标出目标页，点击直达
    expect(
      find.descendant(of: other, matching: find.textContaining('传输与连接')),
      findsOneWidget,
    );
    // 只显示所在大类，不再带原条目的副标题（当前值等）
    expect((tester.widget<ListTile>(other).subtitle! as Text).data, '传输与连接');

    await tester.tap(other);
    await tester.pumpAndSettle();
    // pushReplacement：当前页换成「传输与连接」，不会堆出一串设置页
    expect(find.byType(SettingsCategoryPage), findsOneWidget);
    expect(find.text('传输与连接'), findsOneWidget); // 顶栏标题
    expect(find.text('高级覆盖项'), findsOneWidget);
    expect(find.text('外观'), findsNothing); // 上一页内容已经不在
  });

  testWidgets('设置搜索：高级覆盖项下的条目直达二级页', (tester) async {
    await _pump(
      tester,
      const SettingsCategoryPage(category: SettingsCategory.appearanceLayout),
    );

    await tester.tap(find.byTooltip('搜索设置项'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '接口域名');
    await tester.pumpAndSettle();

    final other = find.widgetWithText(ListTile, '网盘接口域名');
    expect(other, findsOneWidget);
    expect(
      find.descendant(of: other, matching: find.textContaining('高级覆盖项')),
      findsOneWidget,
    );

    await tester.tap(other);
    await tester.pumpAndSettle();
    expect(find.text('正常情况下不宜更改这些选项，否则可能导致相关功能故障'), findsOneWidget);
    expect(find.text('网盘接口域名'), findsOneWidget);
  });

  testWidgets('两栏「我的」：搜索跳转高级覆盖项条目直接在右窗格打开', (tester) async {
    await _pump(tester, const ProfilePage(), size: const Size(1200, 800));

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索设置项'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '接口域名');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, '网盘接口域名'));
    await tester.pumpAndSettle();
    // 在右窗格内打开（左窗格还在、顶栏标题换成二级页），不是整页 push
    expect(find.text('外观与布局'), findsOneWidget);
    expect(find.text('正常情况下不宜更改这些选项，否则可能导致相关功能故障'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('高级覆盖项')),
      findsOneWidget,
    );
  });

  testWidgets('两栏「我的」：详情窗格里搜索其他类别 → 切换选中项', (tester) async {
    await _pump(tester, const ProfilePage(), size: const Size(1200, 800));

    await tester.tap(find.text('传输与连接'));
    await tester.pumpAndSettle();
    expect(find.text('下载目录'), findsOneWidget);

    // 详情窗格标题行里的搜索按钮
    await tester.tap(find.byTooltip('搜索设置项'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '语言');
    await tester.pumpAndSettle();
    expect(find.text('其他设置项'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, '语言'));
    await tester.pumpAndSettle();
    // 左窗格选中项切到「外观与布局」，详情换成该页，搜索态退出
    expect(find.text('外观'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(ListTile, '语言'), findsOneWidget);
  });
}
