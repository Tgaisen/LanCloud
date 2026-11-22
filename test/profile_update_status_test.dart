import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/app_test_scope.dart';

import 'support/profile_page_test_support.dart';

void main() {
  testWidgets('「更新」条目：检测到新版本时显示「检测到更新」副标题（单栏 / 两栏）', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final app = AppEnvironment();
    addTearDown(app.dispose);
    await app.settingsState.store.load();
    final container = createUpdateContainer(
      settings: app.settingsState.store,
      fetch: () async => [
        ReleaseInfo(
          tag: 'v99.0.0',
          version: '99.0.0',
          body: '',
          htmlUrl: '',
          prerelease: false,
          draft: false,
          publishedAt: null,
          assets: const [],
        ),
      ],
    );
    addTearDown(container.dispose);
    final updates = container.read(updateServiceProvider.notifier);
    await updates.initialize();
    await updates.check();
    expect(updates.status, UpdateStatus.available);

    Future<void> pumpProfile() async {
      await tester.pumpWidget(
        ProfileTestProviders.value(
          value: app,
          container: container,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const ProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 单栏：ListTile 副标题
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpProfile();
    expect(find.text('检测到更新'), findsOneWidget);

    // 两栏：左窗格条目副标题
    tester.view.physicalSize = const Size(1200, 800);
    await pumpProfile();
    expect(find.text('检测到更新'), findsOneWidget);
  });
}
