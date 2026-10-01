import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'login_page.dart';
import 'scroll_tint.dart';
import 'settings_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _openWeb(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final account = app.activeAccount;
    final uid = app.activeUid ?? '';
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: app.settings.hideTopBar,
            snap: false,
            pinned: !app.settings.hideTopBar,
            backgroundColor: Color.lerp(
              scheme.surface,
              scheme.surfaceContainerHighest,
              ScrollTint.of(context),
            ),
            scrolledUnderElevation: 0,
            title: Text(l10n.my),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        uid.isEmpty ? '?' : uid.substring(uid.length - 1),
                      ),
                    ),
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
                      child: Text(l10n.switchAccountShort),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.switch_account_outlined),
                        title: Text(l10n.switchAccount),
                        onTap: () => _showAccountSwitcher(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(l10n.removeCurrentAccount),
                        onTap: () => _removeAccount(context, uid),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.public),
                        title: Text(l10n.webManagement),
                        subtitle: Text(l10n.webManagementSubtitle),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () =>
                            _openWeb('https://pc.woozooo.com/mydisk.php'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.restore_from_trash_outlined),
                        title: Text(l10n.recycleBin),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _openWeb(
                          'https://pc.woozooo.com/mydisk.php?item=recycle',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: Text(l10n.settings),
                        subtitle: Text(l10n.settingsSubtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(l10n.about),
                        subtitle: Text(l10n.aboutSubtitle),
                        onTap: () => showAboutDialog(
                          context: context,
                          applicationName: 'LanCloud',
                          applicationVersion: '0.8.9',
                          children: [Text(l10n.aboutText)],
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountSwitcher(BuildContext context) async {
    final app = context.read<AppController>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
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
                  Navigator.of(sheetContext).pop();
                  await app.switchAccount(account.uid);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(context.l10n.addAccount),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              },
            ),
          ],
        ),
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
