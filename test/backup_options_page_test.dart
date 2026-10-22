import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_crypto.dart';
import 'package:lancloud/core/backup/backup_sections.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/backup_options_page.dart';
import 'package:lancloud/ui/backup_unlock_dialog.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

Widget _host(Widget child) => ChangeNotifierProvider<AppController>(
  create: (_) => AppController(),
  child: MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('备份选项使用独立页面，复用应用顶栏；无内容时动作置灰', (tester) async {
    BackupOptionsResult? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showBackupOptionsPage(
                context,
                initialSections: const {},
                confirmLabel: '继续',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupOptionsPage), findsOneWidget);
    expect(find.byType(TopBarOverlayScaffold), findsOneWidget);
    expect(find.widgetWithText(AppBar, '备份选项'), findsOneWidget);
    expect(find.byType(AppBarBackButton), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '继续'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('backup-options-passphrase')),
          )
          .enabled,
      isFalse,
    );
    expect(result, isNull);
  });

  testWidgets('首次设置备份密码可以显示；敏感内容强制加密', (tester) async {
    BackupOptionsResult? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showBackupOptionsPage(
                context,
                initialSections: const {},
                confirmLabel: '继续',
                verifySensitive: () async => true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('常规'), findsNothing);
    expect(find.text('账号信息'), findsNothing);
    expect(find.text('敏感信息'), findsNothing);
    expect(find.text('各账号的快速访问数据'), findsOneWidget);
    expect(find.text('各账号的最近使用数据'), findsOneWidget);
    expect(find.text('敏感信息，等同于账号登录凭据'), findsOneWidget);
    expect(find.text('敏感信息，等同于 WebDAV 登录凭据'), findsOneWidget);

    final sensitiveTile = find.text('账号列表与 Cookie');
    await tester.ensureVisible(sensitiveTile);
    await tester.pumpAndSettle();
    await tester.tap(sensitiveTile);
    await tester.pumpAndSettle();

    final protectionSwitch = tester.widget<M3eSwitchTile>(
      find.widgetWithText(M3eSwitchTile, '加密备份'),
    );
    expect(protectionSwitch.value, isTrue);
    expect(protectionSwitch.enabled, isFalse);
    expect(protectionSwitch.subtitle, '请牢记密码，否则无法恢复数据');
    expect(find.text('请牢记密码，否则无法恢复数据'), findsOneWidget);
    expect(find.text('备份包含敏感信息，为确保数据安全需要加密备份'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('backup-options-passphrase')),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('显示密码'), findsOneWidget);
    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, app_icons.Icons.visibility),
        )
        .onPressed!();
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('backup-options-passphrase')),
          )
          .obscureText,
      isFalse,
    );
    expect(find.byTooltip('隐藏密码'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();
    expect(find.text('请输入备份密码'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('backup-options-passphrase')),
      'backup-secret',
    );
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pumpAndSettle();

    expect(result?.sections, {BackupSection.cookies});
    expect(result?.passphrase, 'backup-secret');
  });

  testWidgets('普通内容可以关闭加密并明确返回不加密', (tester) async {
    BackupOptionsResult? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showBackupOptionsPage(
                context,
                initialSections: const {BackupSection.settings},
                initialPassphrase: 'old-passphrase',
                confirmLabel: '保存',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 来自已保存配置的密码不在界面上提供明文查看入口。
    expect(find.byTooltip('显示密码'), findsNothing);
    await tester.tap(find.text('加密备份'));
    await tester.pumpAndSettle();
    final passphraseField = tester.widget<TextField>(
      find.byKey(const ValueKey('backup-options-passphrase')),
    );
    expect(passphraseField.enabled, isFalse);
    expect(
      find.byKey(const ValueKey('backup-options-passphrase')),
      findsOneWidget,
    );
    expect(find.text('未加密备份，请注意数据安全'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(result?.sections, {BackupSection.settings});
    expect(result?.passphrase, isEmpty);
  });

  testWidgets('解锁弹窗错误口令原地提示，正确口令返回明文', (tester) async {
    final encryption = await BackupCrypto.encrypt(
      '{"app":"lancloud","format":3,"tables":{}}',
      passphrase: 'backup-secret',
      iterations: 1000,
    );
    final content = jsonEncode({
      'app': 'lancloud',
      'format': 3,
      'encryption': encryption,
    });
    UnlockedBackup? unlocked;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              unlocked = await showBackupUnlockDialog(
                context,
                content: content,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('显示密码'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('backup-unlock-passphrase')),
      'wrong-secret',
    );
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(find.text('备份密码错误或备份已损坏'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('backup-unlock-passphrase')),
      'backup-secret',
    );
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(unlocked?.content, contains('"app":"lancloud"'));
    expect(unlocked?.passphrase, 'backup-secret');
  });
}
