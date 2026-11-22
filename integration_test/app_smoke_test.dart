import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/app_runtime_state.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/home_page.dart';
import 'package:lancloud/ui/login_page.dart';
import 'package:lancloud/ui/profile_page.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/app_test_scope.dart';
import '../test/support/transfer_test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('RootShell', () {
    testWidgets('should switch between primary tabs', (tester) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final databaseDirectory = Directory.systemTemp.createTempSync(
        'lancloud_integration_test_db_',
      );
      AppDb.debugDatabaseDirectory = databaseDirectory.path;
      addTearDown(() {
        AppDb.debugDatabaseDirectory = null;
        if (databaseDirectory.existsSync()) {
          databaseDirectory.deleteSync(recursive: true);
        }
      });

      final environment = AppEnvironment();
      addTearDown(environment.dispose);
      environment.runtimeState.ready.value = true;
      environment.settingsState.store
        ..navShowFavorites = true
        ..navShowTransfers = true;
      environment.accountState.store.accounts.add(
        Account(uid: '556911', cookie: 'c', nickname: '集成测试'),
      );
      environment.accountState.store.activeUid = '556911';

      final transfers = buildTransferManagerForEnvironment(environment);
      addTearDown(transfers.dispose);

      await tester.pumpWidget(_shellHost(environment, transfers));
      await _pumpUntilFound(tester, find.byType(RootShell));
      await tester.pumpAndSettle();

      await tester.tap(find.text('传输').last);
      await tester.pumpAndSettle();
      expect(find.byType(TransfersPage), findsOneWidget);

      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);

      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('should accept first-run terms and reach login', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final databaseDirectory = Directory.systemTemp.createTempSync(
        'lancloud_integration_terms_db_',
      );
      AppDb.debugDatabaseDirectory = databaseDirectory.path;
      addTearDown(() {
        AppDb.debugDatabaseDirectory = null;
        if (databaseDirectory.existsSync()) {
          databaseDirectory.deleteSync(recursive: true);
        }
      });

      final environment = AppEnvironment();
      addTearDown(environment.dispose);
      environment.runtimeState.ready.value = true;
      final transfers = buildTransferManagerForEnvironment(environment);
      addTearDown(transfers.dispose);

      await tester.pumpWidget(
        _shellHost(environment, transfers, home: const AgreementGate()),
      );
      await _pumpUntilFound(tester, find.byType(Checkbox));
      await tester.pumpAndSettle();

      final next = find.widgetWithText(FilledButton, '下一步');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.byType(RootShell), findsOneWidget);
      await _pumpUntilFound(tester, find.byType(LoginPage));
      expect(find.byType(LoginPage), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('terms_accepted_version'), isNotNull);
    });
  });
}

Widget _shellHost(
  AppEnvironment environment,
  TransferManager transfers, {
  Widget home = const RootShell(),
}) {
  return appEnvironmentTestTree(
    environment: environment,
    transferManager: transfers,
    child: ProviderScope(
      overrides: [
        appRuntimeStateProvider.overrideWithValue(environment.runtimeState),
        lanzouClientRegistryProvider.overrideWithValue(
          environment.clientRegistry,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLanCloudTheme(
          brightness: Brightness.light,
          seed: LanCloudApp.seed,
          oledDark: false,
        ),
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: home,
      ),
    ),
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('等待组件超时：$finder');
}
