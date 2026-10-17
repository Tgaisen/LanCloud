import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_info.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/update_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReleaseInfo rel(String version, {String body = ''}) => ReleaseInfo(
  tag: 'v$version',
  version: version,
  body: body,
  htmlUrl: 'https://github.com/Tgaisen/LanCloud/releases/tag/v$version',
  prerelease: isPrereleaseVersion(version),
  draft: false,
  publishedAt: DateTime(2026, 1, 1),
  assets: const [],
);

DioException httpError(int status) => DioException(
  requestOptions: RequestOptions(path: '/releases'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/releases'),
    statusCode: status,
  ),
);

/// 打开独立的更新页（与「关于」页同样的独立页形态）。
Future<AppController> pumpUpdatePage(
  WidgetTester tester, {
  bool autoCheck = true,
  Locale locale = const Locale('zh'),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final app = AppController();
  app.settings.updateAutoCheck = autoCheck;
  await app.updates.bind(app.settings);
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const UpdatePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

Finder dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, label),
);

void main() {
  setUp(() {
    UpdateService.debugFetchReleases = null;
    UpdateService.debugNow = DateTime.now;
  });

  tearDown(() {
    UpdateService.debugFetchReleases = null;
    UpdateService.debugNow = DateTime.now;
  });

  testWidgets('更新页：未检测状态与列表组', (tester) async {
    await pumpUpdatePage(tester);

    expect(find.text('未检测更新'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '检测更新'), findsOneWidget);
    // 列表组 1：版本信息（副标题是当前版本，点开构建信息弹窗）+ 更新日志
    expect(find.text('版本信息'), findsOneWidget);
    expect(find.text('$appVersion ($appBuild)'), findsOneWidget);
    expect(find.text('更新日志'), findsOneWidget);
    // 列表组 2：通道默认跟随安装版本类型（当前安装包是测试版）
    expect(find.text('更新通道'), findsOneWidget);
    expect(find.text('测试版'), findsOneWidget);
    expect(find.text('自动检查更新'), findsOneWidget);

    // 版本信息点开的是关于页那个构建信息弹窗
    await tester.tap(find.text('版本信息'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('构建信息'), findsOneWidget);
  });

  testWidgets('检测到新版本：卡片、更新弹窗与两个动作', (tester) async {
    UpdateService.debugFetchReleases = () async => [
      rel(
        '99.0.0',
        body:
            '## 更新日志\n\n'
            '- 新功能\n'
            '- 修复问题\n\n'
            '> Full Changelog: [x](https://example.com)\n\n'
            '## 下载选择\n\n'
            '- Android：优先 arm64-v8a',
      ),
    ];
    final app = await pumpUpdatePage(tester);

    await tester.tap(find.widgetWithText(FilledButton, '检测更新'));
    await tester.pumpAndSettle();

    expect(app.updates.status, UpdateStatus.available);
    expect(find.text('检测到新版本'), findsOneWidget);
    expect(find.text('99.0.0'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '更新'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '更新'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('检测到新版本 99.0.0'), findsOneWidget);
    // 只显示「更新日志」一节：项目符号行 + 末行的详情链接；
    // 引用行与「下载选择」不进弹窗
    expect(find.text('• 新功能'), findsOneWidget);
    expect(find.text('• 修复问题'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.textContaining('Full Changelog'), findsNothing);
    expect(find.textContaining('下载选择'), findsNothing);
    // 两个动作：取消 + 更新（「详情」是正文里的链接，不占动作位）
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(dialogButton('更新'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('更新状态区：图标框 / 文本 / 按钮垂直居中排列', (tester) async {
    await pumpUpdatePage(tester);

    final iconRect = tester.getRect(find.byIcon(app_icons.Icons.update));
    final titleRect = tester.getRect(find.text('未检测更新'));
    final buttonRect = tester.getRect(
      find.widgetWithText(FilledButton, '检测更新'),
    );
    // 三者水平居中对齐（文本独占整行，不再和按钮抢宽度）
    expect(
      iconRect.center.dx,
      moreOrLessEquals(titleRect.center.dx, epsilon: 0.5),
    );
    expect(
      buttonRect.center.dx,
      moreOrLessEquals(titleRect.center.dx, epsilon: 0.5),
    );
    // 垂直顺序：图标框 → 状态文本 → 按钮
    expect(titleRect.top, greaterThan(iconRect.bottom));
    expect(buttonRect.top, greaterThan(titleRect.bottom));
  });

  testWidgets('英文长文案在窄屏下不溢出（失败状态最长）', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    UpdateService.debugFetchReleases = () async => throw httpError(403);
    await pumpUpdatePage(tester, locale: const Locale('en'));

    await tester.tap(find.widgetWithText(FilledButton, 'Check for updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 布局在渲染溢出时会直接让用例失败；这里再确认文案确实是最长的那种
    expect(find.text('Update check failed'), findsNWidgets(2));
    expect(find.text("Couldn't reach GitHub (HTTP 403)"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check again'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('检测开始时状态区高度平滑收起：副标题区域做布局动画', (tester) async {
    // 第一次检测成功 → 「已是最新版本」带副标题
    UpdateService.debugFetchReleases = () async => [rel('1.0.0')];
    await pumpUpdatePage(tester);
    await tester.tap(find.widgetWithText(FilledButton, '检测更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('上次检测于'), findsOneWidget);

    // 第二次检测挂起，停在「检测中」观察布局动画（副标题收起、按钮上移）
    final completer = Completer<List<ReleaseInfo>>();
    UpdateService.debugFetchReleases = () => completer.future;
    final before = tester
        .getRect(find.widgetWithText(FilledButton, '重新检测'))
        .top;

    await tester.tap(find.widgetWithText(FilledButton, '重新检测'));
    await tester.pump();
    final started = tester
        .getRect(find.widgetWithText(FilledButton, '检测中'))
        .top;
    await tester.pump(const Duration(milliseconds: 110));
    final mid = tester.getRect(find.widgetWithText(FilledButton, '检测中')).top;
    await tester.pump(const Duration(milliseconds: 400));
    final settled = tester
        .getRect(find.widgetWithText(FilledButton, '检测中'))
        .top;

    // 动画从原位开始、平滑上移，而不是瞬间跳到位
    expect(started, moreOrLessEquals(before, epsilon: 0.5));
    expect(mid, lessThan(started));
    expect(settled, lessThan(mid));
    // 副标题淡出后不再占位
    expect(find.textContaining('上次检测于'), findsNothing);

    completer.complete([rel('1.0.0')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('上次检测于'), findsOneWidget);
  });

  testWidgets('少动效：状态区布局直接到位，不做尺寸动画', (tester) async {
    SystemMotion.motionMode.value = 'off';
    addTearDown(() => SystemMotion.motionMode.value = 'auto');

    UpdateService.debugFetchReleases = () async => [rel('1.0.0')];
    await pumpUpdatePage(tester);
    await tester.tap(find.widgetWithText(FilledButton, '检测更新'));
    await tester.pumpAndSettle();

    final completer = Completer<List<ReleaseInfo>>();
    UpdateService.debugFetchReleases = () => completer.future;
    await tester.tap(find.widgetWithText(FilledButton, '重新检测'));
    await tester.pump();
    final instant = tester
        .getRect(find.widgetWithText(FilledButton, '检测中'))
        .top;
    await tester.pump(const Duration(milliseconds: 400));
    final settled = tester
        .getRect(find.widgetWithText(FilledButton, '检测中'))
        .top;

    expect(instant, moreOrLessEquals(settled, epsilon: 0.5));

    completer.complete([rel('1.0.0')]);
    await tester.pumpAndSettle();
  });

  testWidgets('检测中：按钮置灰，圆环立即替换图标', (tester) async {
    final completer = Completer<List<ReleaseInfo>>();
    UpdateService.debugFetchReleases = () => completer.future;
    await pumpUpdatePage(tester);

    await tester.tap(find.widgetWithText(FilledButton, '检测更新'));
    await tester.pump();

    expect(find.text('正在检测更新…'), findsOneWidget);
    expect(find.text('上次检测于'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '检测中'),
    );
    expect(button.onPressed, isNull);
    // 圆环不再延迟：进入检测中就直接显示（不先闪一下 update 图标）
    expect(find.byType(M3eLoadingIndicator), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.update), findsNothing);

    completer.complete([rel('99.0.0')]);
    await tester.pumpAndSettle();
    expect(find.text('检测到新版本'), findsOneWidget);
  });

  testWidgets('检测失败：错误码、重新检测，手动检测失败给提示条', (tester) async {
    UpdateService.debugFetchReleases = () async => throw httpError(403);
    final app = await pumpUpdatePage(tester);

    await tester.tap(find.widgetWithText(FilledButton, '检测更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(app.updates.status, UpdateStatus.failed);
    // 卡片标题 + 提示条各一处
    expect(find.text('检测更新失败'), findsNWidgets(2));
    expect(find.text('无法连接至 GitHub (HTTP 403)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重新检测'), findsOneWidget);

    // 提示条约 2 秒后退场，卡片上的失败状态保留
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('检测更新失败'), findsOneWidget);
  });

  testWidgets('更新通道：单选弹窗；切换后清掉旧结果', (tester) async {
    var calls = 0;
    UpdateService.debugFetchReleases = () async {
      calls++;
      return [rel('99.0.0')];
    };
    final app = await pumpUpdatePage(tester, autoCheck: false);
    await tester.tap(find.widgetWithText(FilledButton, '检测更新'));
    await tester.pumpAndSettle();
    expect(app.updates.status, UpdateStatus.available);
    expect(calls, 1);

    await tester.tap(find.text('更新通道'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('正式版'));
    await tester.pumpAndSettle();

    expect(app.settings.updateChannel, 'stable');
    expect(find.text('正式版'), findsOneWidget);
    // 旧通道的结果被清掉：回到未检测更新，且没有偷偷再请求
    expect(app.updates.status, UpdateStatus.idle);
    expect(find.text('未检测更新'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('自动检查更新：开关可切换并落到设置', (tester) async {
    final app = await pumpUpdatePage(tester);
    expect(app.settings.updateAutoCheck, isTrue);

    await tester.tap(find.text('自动检查更新'));
    await tester.pumpAndSettle();
    expect(app.settings.updateAutoCheck, isFalse);
  });

  testWidgets('iOS：卡片显示不支持，隐藏通道与自动检查（列表组 1 保留）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final app = await pumpUpdatePage(tester);

      expect(app.updates.supported, isFalse);
      expect(find.text('当前平台不支持检测更新'), findsOneWidget);
      // 卡片没有按钮
      expect(find.byType(FilledButton), findsNothing);
      // 列表组 1 正常显示，列表组 2 隐藏
      expect(find.text('版本信息'), findsOneWidget);
      expect(find.text('更新日志'), findsOneWidget);
      expect(find.text('更新通道'), findsNothing);
      expect(find.text('自动检查更新'), findsNothing);
    } finally {
      // 必须在本测试体内恢复：框架会在测试体结束后、tearDown 之前断言调试变量
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
