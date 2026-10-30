import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/update_prompt.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_test_scope_test.dart';

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

late UpdateFetcher _fetchReleases;
late UpdateClock _now;

Future<({AppController app, UpdateService updates})> _pumpHost(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final app = AppController();
  await app.settings.load();
  final container = createUpdateContainer(
    settings: app.settings,
    fetch: () => _fetchReleases(),
    clock: () => _now(),
  );
  final updates = container.read(updateServiceProvider.notifier);
  await updates.initialize();
  addTearDown(app.dispose);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    updateTestTree(
      app: app,
      container: container,
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
  return (app: app, updates: updates);
}

void main() {
  setUp(() {
    _fetchReleases = () async => const [];
    _now = DateTime.now;
  });

  testWidgets('自动检测到新版本：在当前页主动弹一次更新弹窗', (tester) async {
    _fetchReleases = () async => [_release('99.0.0')];
    final harness = await _pumpHost(tester);

    await harness.updates.maybeAutoCheck();
    await tester.pumpAndSettle();

    expect(find.text('检测到新版本 99.0.0'), findsOneWidget);
    // 弹窗正文同样走更新日志解析
    expect(find.text('• 新功能'), findsOneWidget);
    // 一次性提醒标记已消费
    expect(harness.updates.autoUpdateNotice, isNull);

    // 取消后本次会话不再重复弹
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('手动检测不会主动弹窗，只更新状态', (tester) async {
    _fetchReleases = () async => [_release('99.0.0')];
    final harness = await _pumpHost(tester);

    await harness.updates.check();
    await tester.pumpAndSettle();

    expect(harness.updates.status, UpdateStatus.available);
    expect(harness.updates.autoUpdateNotice, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
