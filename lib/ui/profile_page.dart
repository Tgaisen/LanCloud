import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import 'login_page.dart';
import 'scroll_tint.dart';

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
                child: Text(uid.isEmpty ? '?' : uid.substring(uid.length - 1)),
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
                  leading: const Icon(Icons.person_add_alt),
                  title: const Text('添加账号'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
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
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('网页版管理'),
                  subtitle: const Text('修改密码、头像等官方功能'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openWeb('https://pc.woozooo.com/mydisk.php'),
                ),
                ListTile(
                  leading: const Icon(Icons.restore_from_trash_outlined),
                  title: const Text('回收站'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () =>
                      _openWeb('https://pc.woozooo.com/mydisk.php?item=recycle'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('深浅色模式'),
                  subtitle: Text(
                    switch (app.settings.themeMode) {
                      'light' => '浅色',
                      'dark' => '深色',
                      _ => '跟随系统',
                    },
                  ),
                  onTap: () => _pickThemeMode(context),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.contrast),
                  title: const Text('OLED 纯黑'),
                  subtitle: const Text('深色模式下用纯黑背景，更省电'),
                  value: app.settings.oledBlack,
                  onChanged: (value) => app.setOledBlack(value),
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('主题色'),
                  trailing: CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(app.settings.themeSeed),
                  ),
                  onTap: () => _pickThemeSeed(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.vertical_align_top),
                  title: const Text('顶栏收起'),
                  subtitle: const Text('列表滑动时收起顶栏（首页已生效）'),
                  value: app.settings.hideTopBar,
                  onChanged: (value) => app.setHideTopBar(value),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vertical_align_bottom),
                  title: const Text('底栏收起'),
                  subtitle: const Text('列表滑动时收起底栏'),
                  value: app.settings.hideBottomBar,
                  onChanged: (value) => app.setHideBottomBar(value),
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('收起类型'),
                  subtitle: Text(
                    app.settings.instantHide ? '即时（到阈值整块收起）' : '同步（跟随滚动）',
                  ),
                  onTap: () => _pickHideType(context),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.smart_button),
                  title: const Text('MD3 悬浮底栏'),
                  subtitle: const Text('带圆角和阴影，浮在内容之上'),
                  value: app.settings.floatingNavBar,
                  onChanged: (value) => app.setFloatingNavBar(value),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.swipe),
                  title: const Text('横滑切换视图'),
                  subtitle: const Text('左右滑动在首页/网盘/传输/我的之间切换'),
                  value: app.settings.swipeTabs,
                  onChanged: (value) => app.setSwipeTabs(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('下载目录'),
                  subtitle: Text(
                    app.settings.downloadDir ?? '默认（应用文档目录/LanCloud）',
                  ),
                  onTap: () => _changeDownloadDir(context),
                ),
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('默认启动页'),
                  subtitle: Text(
                    app.settings.launchPage == 'drive' ? '网盘' : '首页',
                  ),
                  onTap: () => _pickLaunchPage(context),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.cached_outlined),
                  title: const Text('缓存目录数据'),
                  subtitle: const Text('返回上一级时不再重新加载'),
                  value: app.settings.cacheFolders,
                  onChanged: (value) => app.setCacheFolders(value),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('自动加载全部目录内容'),
                  subtitle: const Text('关闭时按页加载，滑到底部再加载下一页'),
                  value: app.settings.loadAllPages,
                  onChanged: (value) => app.setLoadAllPages(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('网络请求间隔'),
                  subtitle: Text(
                    '${app.settings.requestInterval} ms（默认 300，过小可能触发限流）',
                  ),
                  onTap: () => _pickInterval(context),
                ),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('同时上传数量'),
                  subtitle: Text('${app.settings.maxUploads}'),
                  onTap: () => _pickConcurrency(context, true),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('同时下载数量'),
                  subtitle: Text('${app.settings.maxDownloads}'),
                  onTap: () => _pickConcurrency(context, false),
                ),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('网盘接口域名'),
                  subtitle: Text(
                    app.settings.apiHost == 'up'
                        ? 'up.woozooo.com（仅在连接异常时修改）'
                        : 'pc.woozooo.com（仅在连接异常时修改）',
                  ),
                  onTap: () => _pickApiHost(context),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('自定义 User-Agent'),
                  subtitle: Text(
                    app.settings.userAgent.isEmpty
                        ? '默认（模拟桌面浏览器）'
                        : app.settings.userAgent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _editUserAgent(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清空最近使用记录'),
                  onTap: () async {
                    await app.db.clearRecents(uid);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已清空')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  subtitle: const Text('LanCloud · 蓝奏云第三方客户端'),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'LanCloud',
                    applicationVersion: '0.8.9',
                    children: const [
                      Text('自用的蓝奏云第三方客户端，基于非官方接口实现，请勿传播或用于商业用途。'),
                    ],
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

  Future<void> _changeDownloadDir(BuildContext context) async {
    final app = context.read<AppController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('下载目录'),
        content: Text(app.settings.downloadDir ?? '默认（应用文档目录/LanCloud）'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await app.settings.setDownloadDir(null);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复默认目录')),
                );
              }
            },
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                final dir = await FilePicker.platform.getDirectoryPath();
                if (dir != null && dir.isNotEmpty) {
                  await app.settings.setDownloadDir(dir);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('下载目录已设为 $dir')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('选择目录失败：$e')),
                  );
                }
              }
            },
            child: const Text('更改'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLaunchPage(BuildContext context) async {
    final app = context.read<AppController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('默认启动页'),
        children: [
          for (final entry in const [('home', '首页'), ('drive', '网盘')])
            ListTile(
              leading: Icon(
                app.settings.launchPage == entry.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(entry.$2),
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await app.setLaunchPage(entry.$1);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickThemeMode(BuildContext context) async {
    final app = context.read<AppController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('深浅色模式'),
        children: [
          for (final entry in const [
            ('system', '跟随系统'),
            ('light', '浅色'),
            ('dark', '深色'),
          ])
            ListTile(
              leading: Icon(
                app.settings.themeMode == entry.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(entry.$2),
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await app.setThemeMode(entry.$1);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickThemeSeed(BuildContext context) async {
    final app = context.read<AppController>();
    const presets = <int, String>{
      0xFF2E6BE6: '经典蓝',
      0xFF00897B: '青绿',
      0xFF7B4DFF: '紫罗兰',
      0xFFE5533D: '朱红',
      0xFF3F7D20: '橄榄绿',
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('主题色'),
        children: [
          for (final entry in presets.entries)
            ListTile(
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: Color(entry.key),
              ),
              title: Text(entry.value),
              trailing: app.settings.themeSeed == entry.key
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await app.setThemeSeed(entry.key);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickHideType(BuildContext context) async {
    final app = context.read<AppController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('收起类型'),
        children: [
          for (final entry in const [
            (false, '同步（跟随滚动）'),
            (true, '即时（到阈值整块收起）'),
          ])
            ListTile(
              leading: Icon(
                app.settings.instantHide == entry.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(entry.$2),
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await app.setInstantHide(entry.$1);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickInterval(BuildContext context) async {
    final app = context.read<AppController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('网络请求间隔'),
        children: [
          for (final ms in const [0, 100, 300, 500, 1000])
            ListTile(
              title: Text(ms == 0 ? '不间隔' : '$ms ms'),
              trailing: app.settings.requestInterval == ms
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await app.setRequestInterval(ms);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickConcurrency(BuildContext context, bool upload) async {
    final app = context.read<AppController>();
    final max = upload ? 3 : 5;
    final current =
        upload ? app.settings.maxUploads : app.settings.maxDownloads;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(upload ? '同时上传数量' : '同时下载数量'),
        children: [
          for (var i = 1; i <= max; i++)
            ListTile(
              title: Text('$i'),
              trailing: current == i ? const Icon(Icons.check) : null,
              onTap: () async {
                Navigator.of(dialogContext).pop();
                if (upload) {
                  await app.setMaxUploads(i);
                } else {
                  await app.setMaxDownloads(i);
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickApiHost(BuildContext context) async {
    final app = context.read<AppController>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('网盘接口域名'),
        children: [
          for (final entry in const [
            ('pc', 'pc.woozooo.com'),
            ('up', 'up.woozooo.com'),
          ])
            ListTile(
              title: Text(entry.$2),
              trailing: app.settings.apiHost == entry.$1
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await app.setApiHost(entry.$1);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _editUserAgent(BuildContext context) async {
    final app = context.read<AppController>();
    final controller = TextEditingController(text: app.settings.userAgent);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义 User-Agent'),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: const InputDecoration(hintText: '留空表示使用默认值'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              app.setUserAgent('');
            },
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              app.setUserAgent(controller.text.trim());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}