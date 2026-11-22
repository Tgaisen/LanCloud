import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/core/backup/webdav_store.dart';
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

  testWidgets('未配置地址时 WebDAV 操作禁用', (tester) async {
    await harness.pumpPage(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '自动备份'))
          .onChanged,
      isNull,
    );
  });

  testWidgets('WebDAV 密码丢失时提示补录并禁用相关操作', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'webdav_url': 'https://dav.example.com/blue/',
      'webdav_user': 'user',
      'webdav_auto': true,
    });
    await harness.pumpPage(tester);

    expect(find.text('WebDAV 账号配置不完整，请重新填写'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isFalse,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '上传备份')).enabled,
      isFalse,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '从云端恢复')).enabled,
      isFalse,
    );
    expect(harness.fake.webdav.autoBackup, isFalse);
  });

  testWidgets('配置地址后 WebDAV 操作可用', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await harness.pumpPage(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '测试连接')).enabled,
      isTrue,
    );
    expect(find.text('未选择备份内容'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '自动备份'))
          .onChanged,
      isNull,
    );

    await harness.fake.webdav.setBackupSections({BackupSection.settings});
    await tester.pumpWidget(const SizedBox());
    await harness.pumpPage(tester);
    expect(find.text('上次备份：尚未备份'), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '自动备份'))
          .onChanged,
      isNotNull,
    );
  });

  testWidgets('自动备份运行期间禁用上传备份', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await harness.fake.webdav.setBackupSections({BackupSection.favorites});
    await harness.pumpPage(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '上传备份')).enabled,
      isTrue,
    );

    harness.fake.webdavBackupRunning.value = true;
    await tester.pump();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '上传备份')).enabled,
      isFalse,
    );

    harness.fake.webdavBackupRunning.value = false;
    await tester.pump();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '上传备份')).enabled,
      isTrue,
    );
  });

  testWidgets('重置 WebDAV 账号同时清空备份选项和自动备份', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await harness.fake.webdav.setBackupOptions(
      sections: {BackupSection.favorites},
      backupPassphrase: 'backup-secret',
    );
    await harness.fake.webdav.setAutoBackup(true);
    await harness.fake.webdav.markBackup(error: 'network failed');
    await harness.pumpPage(tester);

    await tester.tap(find.text('WebDAV 账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();

    expect(harness.fake.webdav.url, isEmpty);
    expect(harness.fake.webdav.backupPassphrase, isEmpty);
    expect(harness.fake.webdav.backupSections, isEmpty);
    expect(harness.fake.webdav.autoBackup, isFalse);
    expect(harness.fake.webdav.lastSuccessAt, 0);
    expect(harness.fake.webdav.lastAttemptAt, 0);
    expect(harness.fake.webdav.lastBackupError, isEmpty);
    expect(find.text('未配置 WebDAV'), findsOneWidget);
  });

  testWidgets('备份频率弹窗：MD3E 单选列表组（radio 指示），选中即写入', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await harness.fake.webdav.setBackupSections({BackupSection.settings});
    await harness.fake.webdav.setAutoBackup(true);
    await harness.pumpPage(tester);

    // 自动备份打开后才有「备份频率」这一行
    await tester.tap(find.text('备份频率'));
    await tester.pumpAndSettle();

    // 新的单选样式：默认 MD3 弹窗 + 连接式列表组，不是旧的 SimpleDialog
    expect(find.byType(SimpleDialog), findsNothing);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(DialogListGroup)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.byType(M3ePickTile)),
      findsNWidgets(2),
    );
    // 单选控件是 radio
    expect(
      find.descendant(of: dialog, matching: find.byType(Radio<bool>)),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('webdav-interval-supporting-text')),
      findsOneWidget,
    );
    expect(find.text('上次备份：尚未备份'), findsOneWidget);

    // 选「每周」：弹窗关闭并写入，行副标题跟着变
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    expect(harness.fake.webdav.interval, 'weekly');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('每周'), findsOneWidget);
  });

  testWidgets('测试连接与上传备份调用服务', (tester) async {
    await harness.fake.webdav.saveServer(
      url: 'https://dav.example.com/blue/',
      username: 'user',
      password: 'pwd',
      backupPassphrase: 'backup-secret',
      path: WebdavStore.defaultPath,
    );
    await harness.fake.webdav.setBackupSections({BackupSection.favorites});
    await harness.pumpPage(tester);

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(harness.fake.testCount, 1);
    expect(find.text('连接成功'), findsOneWidget);

    // 等第一个提示消失，避免第二条提示排队等待
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('上传备份'));
    await tester.pumpAndSettle();
    expect(harness.fake.uploadCount, 1);
    expect(
      find.text('已上传 lancloud-backup-20261002-181500.json'),
      findsOneWidget,
    );
  });
}
