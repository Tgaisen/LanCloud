import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/backup_page.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'support/backup_page_test_support.dart';

void main() {
  late BackupPageHarness harness;
  setUp(() {
    harness = BackupPageHarness();
    harness.setUp();
  });
  tearDown(() => harness.tearDown());

  testWidgets('恢复确认弹窗：无图标标题，含收藏夹时给保留选项且默认勾选', (tester) async {
    RestoreDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  decision = await showRestoreConfirmDialog(
                    context,
                    preview: BackupService.inspect(
                      '{"app":"lancloud","sections":["favorites"],'
                      '"tables":{"favorites":[{"ref":"existing"}]}}',
                    ),
                    showKeepFavorites: true,
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 标题和其它弹窗一样是无图标的文本
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).icon, isNull);
    expect(
      tester
          .widget<M3ePickTile>(find.widgetWithText(M3ePickTile, '保留原收藏夹内容'))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(decision?.keepFavorites, isTrue);
  });

  testWidgets('恢复确认弹窗：备份不含收藏夹时不显示保留选项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showRestoreConfirmDialog(
                  context,
                  preview: BackupService.inspect(
                    '{"app":"lancloud","tables":{"favorites":[]}}',
                  ),
                  showKeepFavorites: false,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('保留原收藏夹内容'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('确认恢复后真的执行恢复（回归：忙碌保护曾把内层调用吞掉）', (tester) async {
    bool? restored;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  restored = await confirmAndRestore(
                    context,
                    harness.fake,
                    '{"app":"lancloud","tables":{"favorites":[]}}',
                  );
                },
                child: const Text('恢复'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(restored, isTrue);
    expect(harness.fake.restoreCount, 1);
    expect(harness.fake.lastRestoredContent, contains('lancloud'));
  });

  testWidgets('取消恢复弹窗时不做任何恢复', (tester) async {
    bool? restored;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  restored = await confirmAndRestore(
                    context,
                    harness.fake,
                    '{"app":"lancloud"}',
                  );
                },
                child: const Text('恢复'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(restored, isFalse);
    expect(harness.fake.restoreCount, 0);
  });

  testWidgets('恢复敏感凭据前重新验证身份，取消时不写入账号', (tester) async {
    bool? restored;
    const content =
        '{"app":"lancloud","format":3,"sections":["cookies"],'
        '"activeUid":"1","accounts":[{"uid":"1","nickname":"A",'
        '"cookie":"ylogin=1; phpdisk_info=secret"}],"tables":{}}';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  restored = await confirmAndRestore(
                    context,
                    harness.fake,
                    content,
                  );
                },
                child: const Text('恢复'),
              ),
            ),
          ),
        ),
      ),
    );

    harness.fakeAuth.result = CookieAuthResult.canceled;
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(restored, isFalse);
    expect(harness.fakeAuth.calls, 1);
    expect(harness.fake.restoreCount, 0);

    harness.fakeAuth.result = CookieAuthResult.failed;
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(restored, isFalse);
    expect(harness.fakeAuth.calls, 2);
    expect(harness.fake.restoreCount, 0);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    harness.fakeAuth.result = CookieAuthResult.ok;
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(restored, isTrue);
    expect(harness.fakeAuth.calls, 3);
    expect(harness.fake.restoreCount, 1);
  });

  testWidgets('仅恢复数据时明确跳过账号恢复', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => confirmAndRestore(
                  context,
                  harness.fake,
                  '{"app":"lancloud","tables":{"favorites":[]}}',
                  restoreAccounts: false,
                ),
                child: const Text('恢复数据'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('恢复数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();

    expect(harness.fake.restoreCount, 1);
    expect(harness.fake.lastRestoreAccounts, isFalse);
  });
}
