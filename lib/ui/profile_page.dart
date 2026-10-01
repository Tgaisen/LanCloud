import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
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
            title: const Text('我的'),
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
                    title: Text(account?.nickname ?? '未登录'),
                    subtitle: Text('UID: $uid'),
                    trailing: FilledButton.tonal(
                      onPressed: () => _showAccountSwitcher(context),
                      child: const Text('切换'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.switch_account_outlined),
                        title: const Text('切换账号'),
                        onTap: () => _showAccountSwitcher(context),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('移除当前账号'),
                        onTap: () => _removeAccount(context, uid),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('设置'),
                    subtitle: const Text('外观、行为、连接与高级覆盖项'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.public),
                        title: const Text('网页版管理'),
                        subtitle: const Text('修改密码、头像等官方功能'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () =>
                            _openWeb('https://pc.woozooo.com/mydisk.php'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.restore_from_trash_outlined),
                        title: const Text('回收站'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _openWeb(
                          'https://pc.woozooo.com/mydisk.php?item=recycle',
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
                title: Text(account.nickname),
                subtitle: Text('UID: ${account.uid}'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await app.switchAccount(account.uid);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('添加账号'),
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
        title: const Text('移除账号'),
        content: Text('将从本机移除账号 $uid 及其登录信息，云端文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok == true) await app.removeAccount(uid);
  }
}
