import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/backup_options_page.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

import 'support/backup_page_test_support.dart';

void main() {
  late BackupPageHarness harness;
  setUp(() {
    harness = BackupPageHarness();
    harness.setUp();
  });
  tearDown(() => harness.tearDown());

  testWidgets('备份页显示本地与 WebDAV 分组', (tester) async {
    await harness.pumpPage(tester);

    expect(find.text('本地备份'), findsOneWidget);
    expect(find.text('立即备份'), findsOneWidget);
    expect(find.text('从文件恢复'), findsOneWidget);
    expect(find.text('WebDAV 账号'), findsOneWidget);
    expect(find.text('备份选项'), findsOneWidget);
    expect(find.text('自动备份'), findsOneWidget);
    expect(find.text('未配置 WebDAV'), findsOneWidget);
    expect(find.textContaining('上次备份'), findsNothing);
    final backupNowTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '立即备份'),
    );
    expect(
      (backupNowTile.trailing! as Icon).icon,
      app_icons.Icons.chevron_right,
    );
    final backupOptionsTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '备份选项'),
    );
    expect(
      (backupOptionsTile.trailing! as Icon).icon,
      app_icons.Icons.chevron_right,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '备份选项'),
        matching: find.byIcon(app_icons.Icons.tune),
      ),
      findsOneWidget,
    );
    // 旧的两个开关搬进「备份内容」弹窗
    expect(find.text('备份包含 Cookie'), findsNothing);
    expect(find.text('备份包含 WebDAV 账号'), findsNothing);
    // “备份选项”行只保留标题，不再显示挤占空间的内容摘要小标题
    expect(find.text('未选择'), findsNothing);
    // 云端备份已并入 WebDAV 分组，不再单独显示小标题
    expect(find.text('云端备份'), findsNothing);
  });

  testWidgets('立即备份：先勾选备份内容，再交给系统保存对话框', (tester) async {
    await harness.pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();

    // 独立页面默认一项都不勾，“继续”不可用
    final optionsPage = find.byType(BackupOptionsPage);
    expect(optionsPage, findsOneWidget);
    expect(
      find.descendant(of: optionsPage, matching: find.text('备份')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: optionsPage, matching: find.byType(AppBarBackButton)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '继续'))
          .onPressed,
      isNull,
    );
    // 常规 2 + 账号信息 2 + 敏感信息 2；账号条目只在勾 Cookie 时随备份写入，
    // 所以没有单独的「账号列表」分项
    final l10n = AppLocalizationsZh();
    expect(
      find.descendant(of: optionsPage, matching: find.byType(M3ePickTile)),
      findsNWidgets(6),
    );
    // 保护备份与备份内容各一组
    expect(
      find.descendant(of: optionsPage, matching: find.byType(SegmentedList)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionQuick),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: optionsPage,
        matching: find.text(l10n.backupSectionCookies),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: optionsPage, matching: find.text('设置项')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(harness.fake.saveCount, 1);
    expect(harness.fake.lastSections, {BackupSection.settings});
    expect(harness.fake.lastPassphrase, isNull);
    expect(harness.savedCalls, hasLength(1));
    expect(
      '${harness.savedCalls.single.arguments['mime']}',
      'application/json',
    );
    expect(
      '${harness.savedCalls.single.arguments['fileName']}',
      endsWith('.json'),
    );
    expect(find.textContaining('lancloud-backup-test.json'), findsOneWidget);
  });

  testWidgets('系统保存对话框取消时不提示', (tester) async {
    harness.saveResult = null;
    await harness.pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('收藏夹'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(harness.savedCalls, hasLength(1));
    expect(find.textContaining('已保存到'), findsNothing);
  });

  testWidgets('生成备份期间显示加载弹窗，完成后再打开系统保存页', (tester) async {
    harness.fake.exportGate = Completer<void>();
    await harness.pumpPage(tester);

    await tester.tap(find.text('立即备份'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BackupOptionsPage),
        matching: find.text('设置项'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在生成备份'), findsOneWidget);
    expect(harness.savedCalls, isEmpty);

    harness.fake.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('正在生成备份'), findsNothing);
    expect(harness.savedCalls, hasLength(1));
  });
}
