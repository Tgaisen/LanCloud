import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/data/account_store.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'about_page.dart';
import 'common.dart';
import 'cookie_sheet.dart';
import 'login_page.dart';
import 'settings_page.dart';
import 'web_page.dart';

/// 打开「我的」底部弹窗（原底栏视图内容整体搬到这里）。
Future<void> showProfileSheet(BuildContext context) {
  return showAppSheet<void>(context, child: const ProfileSheet());
}

/// 「我的」弹窗内容：账号卡片 + 网页版/回收站 + 设置/关于。
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  void _openWeb(BuildContext context, String url, String title) {
    final app = context.read<AppController>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebPage(
          title: title,
          url: url,
          cookie: app.activeAccount?.cookie,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final account = app.activeAccount;
    final uid = app.activeUid ?? '';
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedList(
            children: [
              ListTile(
                leading: CircleAvatar(child: Text(_avatarInitial(account, uid))),
                title: Text(
                  account == null
                      ? l10n.notLoggedIn
                      : account.nickname.isEmpty
                          ? l10n.accountUid(uid)
                          : account.nickname,
                ),
                subtitle: Text(l10n.uidLabel(uid)),
                trailing: FilledButton.tonal(
                  onPressed: () => _showAccountSwitcher(context),
                  child: Text(l10n.manage),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l10n.showCookie),
                subtitle: Text(l10n.showCookieSubtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: account != null,
                onTap: account == null
                    ? null
                    : () => showCookieFlow(context, account),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedList(
            children: [
              ListTile(
                leading: const Icon(Icons.public),
                title: Text(l10n.webManagement),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openWeb(
                  context,
                  'https://pc.woozooo.com/mydisk.php',
                  l10n.webManagement,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.restore_from_trash_outlined),
                title: Text(l10n.recycleBin),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openWeb(
                  context,
                  'https://pc.woozooo.com/mydisk.php?item=recycle',
                  l10n.recycleBin,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedList(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(l10n.settings),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.about),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _avatarInitial(Account? account, String uid) {
    final name = account == null
        ? ''
        : account.nickname.isNotEmpty
            ? account.nickname
            : uid;
    if (name.isEmpty) return '?';
    return name.substring(0, 1);
  }

  Future<void> _showAccountSwitcher(BuildContext context) async {
    final app = context.read<AppController>();
    await showAppSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final account in app.accounts.accounts)
            ListTile(
              leading: Icon(
                account.uid == app.activeUid
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                account.nickname.isEmpty
                    ? context.l10n.accountUid(account.uid)
                    : account.nickname,
              ),
              subtitle: Text(context.l10n.uidLabel(account.uid)),
              onTap: () async {
                Navigator.of(context).pop();
                await app.switchAccount(account.uid);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(context.l10n.addAccount),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(context.l10n.logout),
            onTap: () {
              final uid = app.activeUid;
              Navigator.of(context).pop();
              if (uid != null) _removeAccount(context, uid);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _removeAccount(BuildContext context, String uid) async {
    final app = context.read<AppController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.removeAccountTitle),
        content: Text(context.l10n.removeAccountMessage(uid)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (ok == true) await app.removeAccount(uid);
  }
}
