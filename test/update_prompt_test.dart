import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/update_prompt.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReleaseInfo _release(String version) => ReleaseInfo(
  tag: 'v$version',
  version: version,
  body: '## 更新日志\n\n- 新功能',
  htmlUrl: 'https://github.com/Tgaisen/LanCloud/releases/tag/v$version',
  prerelease: isPrereleaseVersion(version),
  draft: false,
  publishedAt: null,
  assets: const [],
);

Future<AppController> _pumpHost(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final app = AppController();
  await app.settings.load();
  await app.updates.bind(app.settings);
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const UpdatePromptHost(
          child: Scaffold(body: Center(child: Text('home'))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
  setUp(() {
    UpdateService.debugFetchReleases = null;
    UpdateService.debugNow = DateTime.now;
  });

  tearDown(() {
    UpdateService.debugFetchReleases = null;
    UpdateService.debugNow = DateTime.now;
  });

  testWidgets('自动检测到新版本：在当前页主动弹一次更新弹窗', (tester) async {
    UpdateService.debugFetchReleases = () async => [_release('99.0.0')];
    final app = await _pumpHost(tester);

    await app.updates.maybeAutoCheck();
    await tester.pumpAndSettle();

    expect(find.text('检测到新版本 99.0.0'), findsOneWidget);
    // 弹窗正文同样走更新日志解析
    expect(find.text('• 新功能'), findsOneWidget);
    // 一次性提醒标记已消费
    expect(app.updates.autoUpdateNotice, isNull);

    // 取消后本次会话不再重复弹
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('手动检测不会主动弹窗，只更新状态', (tester) async {
    UpdateService.debugFetchReleases = () async => [_release('99.0.0')];
    final app = await _pumpHost(tester);

    await app.updates.check();
    await tester.pumpAndSettle();

    expect(app.updates.status, UpdateStatus.available);
    expect(app.updates.autoUpdateNotice, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
