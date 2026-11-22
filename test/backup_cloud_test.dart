import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
import 'package:lancloud/core/cookie_auth.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/backup_page.dart';
import 'package:lancloud/ui/common.dart';
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

  testWidgets('上传备份：生成阶段弹窗，随后显示上传进度线', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await harness.fake.webdav.setBackupSections({BackupSection.favorites});
    harness.fake.uploadGenerationGate = Completer<void>();
    harness.fake.uploadGate = Completer<void>();
    await harness.pumpPage(tester);

    await tester.tap(find.text('上传备份'));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在生成备份'), findsOneWidget);
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);

    harness.fake.uploadGenerationGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在生成备份'), findsNothing);
    expect(find.byType(M3eLinearProgressIndicator), findsOneWidget);

    harness.fake.uploadGate!.complete();
    await tester.pumpAndSettle();
    expect(harness.fake.uploadCount, 1);
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);
    expect(
      find.text('已上传 lancloud-backup-20261002-181500.json'),
      findsOneWidget,
    );
  });

  testWidgets('云端恢复：选择版本弹窗带标题、分层时间与最新标记；进度线不残留', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    final now = DateTime.now();
    final newest = now.subtract(const Duration(minutes: 10));
    final older = now.subtract(const Duration(days: 3));
    harness.fake.remoteEntries = [
      WebdavEntry(
        name: BackupService.latestName,
        href: '',
        size: 2048,
        modified: newest,
      ),
      WebdavEntry(
        name: 'lancloud-backup-20261010-120000.json',
        href: '',
        size: 0,
        modified: older,
      ),
    ];
    harness.fake.remoteGate = Completer<void>();
    await harness.pumpPage(tester);

    await tester.tap(find.text('从云端恢复'));
    await tester.pump();
    // 列表还在拉取：顶栏进度线显示（粗细与 WebView 进度条一致，4dp）
    expect(find.byType(M3eLinearProgressIndicator), findsOneWidget);
    expect(kBackupProgressBar.preferredSize.height, 4);

    harness.fake.remoteGate!.complete();
    await tester.pumpAndSettle();

    // 弹窗打开时进度线已经收起
    expect(find.byType(M3eLinearProgressIndicator), findsNothing);
    expect(find.text('选择恢复版本'), findsOneWidget);
    // 最新一条（列表第一行）带「· 最新版本」；时间用分层相对格式
    final l10n = AppLocalizationsZh();
    expect(
      find.text('${formatRelativeTime(l10n, newest)} · 2.0 KB · 最新版本'),
      findsOneWidget,
    );
    // 其它条目没有「最新版本」标记，时间同样走分层格式（如「10月14日」）
    final olderTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'lancloud-backup-20261010-120000.json'),
    );
    final olderSubtitle = (olderTile.subtitle! as Text).data!;
    expect(olderSubtitle.contains('最新版本'), isFalse);
    expect(olderSubtitle, matches(RegExp(r'^\d{1,2}月\d{1,2}日$')));

    // 点空白处关掉弹窗
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('选择恢复版本'), findsNothing);
  });

  testWidgets('「上次备份」日期：今天 / 昨天 / yyyy-MM-dd', (tester) async {
    final now = DateTime.now();
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    // 页面 initState 会重新 load 存储，所以把状态放进 mock 的 SharedPreferences
    Future<void> pumpWith(int millis) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'webdav_backup_sections': ['settings'],
        'webdav_auto': true,
        'webdav_last_backup_at': millis,
      });
      // 先卸载旧页面：否则同类型 widget 复用 State，不会重新 load 存储
      await tester.pumpWidget(const SizedBox());
      await harness.pumpPage(tester);
    }

    await pumpWith(now.millisecondsSinceEpoch);
    await tester.tap(find.text('备份频率'));
    await tester.pumpAndSettle();
    expect(find.text('上次备份：今天'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await pumpWith(
      now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    await tester.tap(find.text('备份频率'));
    await tester.pumpAndSettle();
    expect(find.text('上次备份：昨天'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final old = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    await pumpWith(old);
    await tester.tap(find.text('备份频率'));
    await tester.pumpAndSettle();
    expect(find.text('上次备份：${formatDateShort(old)}'), findsOneWidget);
  });

  testWidgets('敏感云端备份上传前不再重复验证身份', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await harness.fake.webdav.setBackupOptions(
      sections: {BackupSection.cookies},
      backupPassphrase: 'backup-secret',
    );
    harness.fakeAuth.result = CookieAuthResult.canceled;
    await harness.pumpPage(tester);

    // 敏感分项在“备份选项”阶段已授权；手动上传与自动备份一致，不再重复验证。
    await tester.tap(find.text('上传备份'));
    await tester.pumpAndSettle();
    expect(harness.fakeAuth.calls, 0);
    expect(harness.fake.uploadCount, 1);
    expect(harness.fake.lastSections, contains(BackupSection.cookies));
  });
}
