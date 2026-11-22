import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/backup_options_page.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/backup_page_test_support.dart';

void main() {
  late BackupPageHarness harness;
  setUp(() {
    harness = BackupPageHarness();
    harness.setUp();
  });
  tearDown(() => harness.tearDown());

  testWidgets('WebDAV 的备份选项会保存下来，只影响云端上传', (tester) async {
    await harness.pumpPage(tester);

    await tester.tap(find.text('备份选项'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '备份选项'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('收藏夹'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(harness.fake.webdav.backupSections, {BackupSection.favorites});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('webdav_backup_sections'), ['favorites']);
    expect(find.text('备份选项'), findsOneWidget);
  });

  testWidgets('敏感项勾选前验证身份，通过后本次运行不再重复验证', (tester) async {
    harness.fakeAuth.result = CookieAuthResult.canceled;
    await harness.pumpPage(tester);

    await tester.tap(find.text('备份选项'));
    await tester.pumpAndSettle();
    final optionsPage = find.byType(BackupOptionsPage);
    final l10n = AppLocalizationsZh();

    // 验证被取消：Cookie 保持未勾选
    await tester.tap(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionCookies),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.fakeAuth.calls, 1);
    expect(
      tester
          .widget<M3ePickTile>(
            find.widgetWithText(M3ePickTile, l10n.backupSectionCookies),
          )
          .selected,
      isFalse,
    );

    // 验证通过后正常勾选
    harness.fakeAuth.result = CookieAuthResult.ok;
    await tester.tap(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionCookies),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.fakeAuth.calls, 2);
    expect(
      tester
          .widget<M3ePickTile>(
            find.widgetWithText(M3ePickTile, l10n.backupSectionCookies),
          )
          .selected,
      isTrue,
    );

    // 本次运行已验证过：再勾 WebDav 账号不再弹验证
    harness.fakeAuth.result = CookieAuthResult.canceled;
    await tester.tap(
      find.descendant(of: optionsPage, matching: find.text(l10n.webdavAccount)),
    );
    await tester.pumpAndSettle();
    expect(harness.fakeAuth.calls, 2);
    expect(
      tester
          .widget<M3ePickTile>(
            find.widgetWithText(M3ePickTile, l10n.webdavAccount),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('导出敏感备份必须设置口令，并把口令交给加密层', (tester) async {
    await harness.pumpPage(tester);
    final l10n = AppLocalizationsZh();

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.backupSectionCookies));
    await tester.pumpAndSettle();
    expect(find.text('保护备份'), findsOneWidget);
    expect(
      tester
          .widget<M3eSwitchTile>(find.widgetWithText(M3eSwitchTile, '加密备份'))
          .enabled,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('backup-options-passphrase')),
      'backup-secret',
    );
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(harness.fake.lastSections, contains(BackupSection.cookies));
    expect(harness.fake.lastPassphrase, 'backup-secret');
    expect(harness.savedCalls, hasLength(1));
  });
}
