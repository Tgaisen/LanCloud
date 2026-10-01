import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import 'scroll_tint.dart';

/// 独立设置页：分类卡片 + 高级覆盖项二级页 + 全量搜索。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _Entry {
  const _Entry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.category,
    required this.build,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final String category;
  final Widget Function(BuildContext context, AppController app) build;
}

class _SettingsPageState extends State<SettingsPage> {
  bool _searching = false;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Entry> _entries(AppController app) => [
        _Entry(
          id: 'theme_mode',
          title: '深浅色模式',
          subtitle: switch (app.settings.themeMode) {
            'light' => '浅色',
            'dark' => '深色',
            _ => '跟随系统',
          },
          keywords: const ['主题', '夜间', '深色', '浅色'],
          category: '外观',
          build: (context, app) => ListTile(
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
        ),
        _Entry(
          id: 'oled',
          title: 'OLED 纯黑',
          subtitle: '深色模式下用纯黑背景，更省电',
          keywords: const ['纯黑', '省电', 'oled'],
          category: '外观',
          build: (context, app) => SwitchListTile(
            secondary: const Icon(Icons.contrast),
            title: const Text('OLED 纯黑'),
            subtitle: const Text('深色模式下用纯黑背景，更省电'),
            value: app.settings.oledBlack,
            onChanged: (value) => app.setOledBlack(value),
          ),
        ),
        _Entry(
          id: 'theme_seed',
          title: '主题色',
          subtitle: _seedName(app.settings.themeSeed),
          keywords: const ['配色', '颜色', '主题'],
          category: '外观',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题色'),
            subtitle: Text(_seedName(app.settings.themeSeed)),
            trailing: CircleAvatar(
              radius: 12,
              backgroundColor: Color(app.settings.themeSeed),
            ),
            onTap: () => _pickThemeSeed(context),
          ),
        ),
        _Entry(
          id: 'hide_top_bar',
          title: '顶栏收起',
          subtitle: '列表滑动时收起顶栏',
          keywords: const ['顶栏', '滑动隐藏', '收起'],
          category: '外观',
          build: (context, app) => SwitchListTile(
            secondary: const Icon(Icons.vertical_align_top),
            title: const Text('顶栏收起'),
            subtitle: const Text('列表滑动时收起顶栏'),
            value: app.settings.hideTopBar,
            onChanged: (value) => app.setHideTopBar(value),
          ),
        ),
        _Entry(
          id: 'hide_bottom_bar',
          title: '底栏收起',
          subtitle: '列表滑动时收起底栏',
          keywords: const ['底栏', '滑动隐藏', '收起'],
          category: '外观',
          build: (context, app) => SwitchListTile(
            secondary: const Icon(Icons.vertical_align_bottom),
            title: const Text('底栏收起'),
            subtitle: const Text('列表滑动时收起底栏'),
            value: app.settings.hideBottomBar,
            onChanged: (value) => app.setHideBottomBar(value),
          ),
        ),
        _Entry(
          id: 'floating_nav',
          title: 'MD3 悬浮底栏',
          subtitle: '带圆角和阴影，浮在内容之上',
          keywords: const ['底栏', '悬浮', 'md3'],
          category: '外观',
          build: (context, app) => SwitchListTile(
            secondary: const Icon(Icons.smart_button),
            title: const Text('MD3 悬浮底栏'),
            subtitle: const Text('带圆角和阴影，浮在内容之上'),
            value: app.settings.floatingNavBar,
            onChanged: (value) => app.setFloatingNavBar(value),
          ),
        ),
        _Entry(
          id: 'swipe_tabs',
          title: '横滑切换视图',
          subtitle: '左右滑动在首页/网盘/传输/我的之间切换',
          keywords: const ['滑动', '手势', 'tab'],
          category: '外观',
          build: (context, app) => SwitchListTile(
            secondary: const Icon(Icons.swipe),
            title: const Text('横滑切换视图'),
            subtitle: const Text('左右滑动在首页/网盘/传输/我的之间切换'),
            value: app.settings.swipeTabs,
            onChanged: (value) => app.setSwipeTabs(value),
          ),
        ),
        _Entry(
          id: 'download_dir',
          title: '下载目录',
          subtitle: app.settings.downloadDir ?? '默认（应用文档目录/LanCloud）',
          keywords: const ['下载', '目录', '保存位置'],
          category: '行为',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('下载目录'),
            subtitle: Text(
              app.settings.downloadDir ?? '默认（应用文档目录/LanCloud）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _changeDownloadDir(context),
          ),
        ),
        _Entry(
          id: 'launch_page',
          title: '默认启动页',
          subtitle: app.settings.launchPage == 'drive' ? '网盘' : '首页',
          keywords: const ['启动', '首页', '网盘'],
          category: '行为',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('默认启动页'),
            subtitle: Text(app.settings.launchPage == 'drive' ? '网盘' : '首页'),
            onTap: () => _pickLaunchPage(context),
          ),
        ),
        _Entry(
          id: 'cache_folders',
          title: '缓存目录数据',
          subtitle: '返回上一级时不再重新加载',
          keywords: const ['缓存', '目录'],
          category: '行为',
          build: (context, app) => SwitchListTile(
            secondary: const Icon(Icons.cached_outlined),
            title: const Text('缓存目录数据'),
            subtitle: const Text('返回上一级时不再重新加载'),
            value: app.settings.cacheFolders,
            onChanged: (value) => app.setCacheFolders(value),
          ),
        ),
        _Entry(
          id: 'load_all_pages',
          title: '自动加载全部目录内容',
          subtitle: '关闭时按页加载，滑到底部再加载下一页',
          keywords: const ['分页', '加载', '目录'],
          category: '行为',
          build: (context, app) => SwitchListTile(
            secondary: const Icon(Icons.download_for_offline_outlined),
            title: const Text('自动加载全部目录内容'),
            subtitle: const Text('关闭时按页加载，滑到底部再加载下一页'),
            value: app.settings.loadAllPages,
            onChanged: (value) => app.setLoadAllPages(value),
          ),
        ),
        _Entry(
          id: 'interval',
          title: '网络请求间隔',
          subtitle: '${app.settings.requestInterval} ms（默认 300，过小可能触发限流）',
          keywords: const ['间隔', '限流', '风控', '请求'],
          category: '连接',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('网络请求间隔'),
            subtitle: Text(
              '${app.settings.requestInterval} ms（默认 300，过小可能触发限流）',
            ),
            onTap: () => _pickInterval(context),
          ),
        ),
        _Entry(
          id: 'max_uploads',
          title: '同时上传数量',
          subtitle: '${app.settings.maxUploads}',
          keywords: const ['上传', '并发'],
          category: '连接',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('同时上传数量'),
            subtitle: Text('${app.settings.maxUploads}'),
            onTap: () => _pickConcurrency(context, true),
          ),
        ),
        _Entry(
          id: 'max_downloads',
          title: '同时下载数量',
          subtitle: '${app.settings.maxDownloads}',
          keywords: const ['下载', '并发'],
          category: '连接',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('同时下载数量'),
            subtitle: Text('${app.settings.maxDownloads}'),
            onTap: () => _pickConcurrency(context, false),
          ),
        ),
        _Entry(
          id: 'api_host',
          title: '网盘接口域名',
          subtitle: app.settings.apiHost == 'up' ? 'up.woozooo.com' : 'pc.woozooo.com',
          keywords: const ['域名', '接口', '连接异常', 'pc', 'up'],
          category: '高级覆盖项',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('网盘接口域名'),
            subtitle: Text(
              app.settings.apiHost == 'up' ? 'up.woozooo.com' : 'pc.woozooo.com',
            ),
            onTap: () => _pickApiHost(context),
          ),
        ),
        _Entry(
          id: 'upload_domain',
          title: '上传域名',
          subtitle: app.settings.uploadDomain.isEmpty
              ? '默认（up.woozooo.com）'
              : app.settings.uploadDomain,
          keywords: const ['上传', '域名', 'up'],
          category: '高级覆盖项',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('上传域名'),
            subtitle: Text(
              app.settings.uploadDomain.isEmpty
                  ? '默认（up.woozooo.com）'
                  : app.settings.uploadDomain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _editUploadDomain(context),
          ),
        ),
        _Entry(
          id: 'share_domain',
          title: '分享链接域名',
          subtitle: app.settings.shareDomain.isEmpty
              ? '默认（自动尝试内置镜像）'
              : app.settings.shareDomain,
          keywords: const ['分享', '域名', '镜像', '链接'],
          category: '高级覆盖项',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('分享链接域名'),
            subtitle: Text(
              app.settings.shareDomain.isEmpty
                  ? '默认（自动尝试内置镜像）'
                  : app.settings.shareDomain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _editShareDomain(context),
          ),
        ),
        _Entry(
          id: 'user_agent',
          title: '自定义 User-Agent',
          subtitle: app.settings.userAgent.isEmpty
              ? '默认（模拟桌面浏览器）'
              : app.settings.userAgent,
          keywords: const ['ua', 'user-agent', '浏览器'],
          category: '高级覆盖项',
          build: (context, app) => ListTile(
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
        ),
        _Entry(
          id: 'clear_recents',
          title: '清空最近使用记录',
          subtitle: '删除首页最近使用条目',
          keywords: const ['最近', '清空', '记录'],
          category: '数据',
          build: (context, app) => ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清空最近使用记录'),
            subtitle: const Text('删除首页最近使用条目'),
            onTap: () async {
              await app.db.clearRecents(app.activeUid ?? '');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清空')),
                );
              }
            },
          ),
        ),
        _Entry(
          id: 'about',
          title: '关于',
          subtitle: 'LanCloud · 蓝奏云第三方客户端',
          keywords: const ['版本', '关于', '开源', '协议'],
          category: '数据',
          build: (context, app) => ListTile(
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
        ),
      ];

  String _seedName(int seed) => const {
        0xFF2E6BE6: '经典蓝',
        0xFF00897B: '青绿',
        0xFF7B4DFF: '紫罗兰',
        0xFFE5533D: '朱红',
        0xFF3F7D20: '橄榄绿',
      }[seed] ??
      '自定义';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final entries = _entries(app);
    final query = _search.text.trim().toLowerCase();

    final matching = entries
        .where((e) =>
            e.title.toLowerCase().contains(query) ||
            e.subtitle.toLowerCase().contains(query) ||
            e.category.toLowerCase().contains(query) ||
            e.keywords.any((k) => k.toLowerCase().contains(query)))
        .toList();

    return ScrollTint(
      child: Builder(
        builder: (context) {
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
                  title: _searching
                      ? TextField(
                          controller: _search,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: '搜索设置',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        )
                      : const Text('设置'),
                  actions: [
                    IconButton(
                      tooltip: _searching ? '关闭搜索' : '搜索设置',
                      icon: Icon(_searching ? Icons.close : Icons.search),
                      onPressed: () {
                        setState(() {
                          _searching = !_searching;
                          if (!_searching) _search.clear();
                        });
                      },
                    ),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      _searching
                          ? _buildSearchResults(context, app, matching)
                          : _buildCategories(context, app, entries),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildCategories(
    BuildContext context,
    AppController app,
    List<_Entry> entries,
  ) {
    final groups = <String, List<_Entry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.category, () => []).add(e);
    }
    final widgets = <Widget>[];
    for (final name in groups.keys) {
      if (name == '高级覆盖项') {
        widgets
          ..add(_sectionTitle(context, name))
          ..add(
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('高级覆盖项'),
                subtitle: const Text('接口/上传/分享域名与自定义 UA'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const _AdvancedPage()),
                ),
              ),
            ),
          );
        continue;
      }
      widgets
        ..add(_sectionTitle(context, name))
        ..add(
          Card(
            child: Column(
              children: [
                for (final e in groups[name]!) e.build(context, app),
              ],
            ),
          ),
        );
    }
    return widgets;
  }

  List<Widget> _buildSearchResults(
    BuildContext context,
    AppController app,
    List<_Entry> matching,
  ) {
    if (_search.text.trim().isEmpty) {
      return [
        const SizedBox(height: 48),
        const Center(
          child: Text('输入关键词搜索设置，如：域名、收起、下载、并发'),
        ),
      ];
    }
    if (matching.isEmpty) {
      return [
        const SizedBox(height: 48),
        const Center(child: Text('没有匹配的设置项')),
      ];
    }
    return [
      Card(
        child: Column(
          children: [
            for (final e in matching) e.build(context, app),
          ],
        ),
      ),
    ];
  }

  Widget _sectionTitle(BuildContext context, String name) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          name,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );

  static Future<void> _changeDownloadDir(BuildContext context) async {
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
              await app.setDownloadDir(null);
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
                  await app.setDownloadDir(dir);
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

  static Future<void> _pickRadio<T>(
    BuildContext context, {
    required String title,
    required List<(T, String)> options,
    required T current,
    required Future<void> Function(T) onSelect,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final entry in options)
            ListTile(
              leading: Icon(
                current == entry.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(entry.$2),
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await onSelect(entry.$1);
              },
            ),
        ],
      ),
    );
  }

  static Future<void> _pickLaunchPage(BuildContext context) {
    final app = context.read<AppController>();
    return _pickRadio(
      context,
      title: '默认启动页',
      options: const [('home', '首页'), ('drive', '网盘')],
      current: app.settings.launchPage,
      onSelect: (value) => app.setLaunchPage(value),
    );
  }

  static Future<void> _pickThemeMode(BuildContext context) {
    final app = context.read<AppController>();
    return _pickRadio(
      context,
      title: '深浅色模式',
      options: const [
        ('system', '跟随系统'),
        ('light', '浅色'),
        ('dark', '深色'),
      ],
      current: app.settings.themeMode,
      onSelect: (value) => app.setThemeMode(value),
    );
  }

  static Future<void> _pickApiHost(BuildContext context) {
    final app = context.read<AppController>();
    return _pickRadio(
      context,
      title: '网盘接口域名',
      options: const [
        ('pc', 'pc.woozooo.com'),
        ('up', 'up.woozooo.com'),
      ],
      current: app.settings.apiHost,
      onSelect: (value) => app.setApiHost(value),
    );
  }

  static Future<void> _pickThemeSeed(BuildContext context) async {
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

  static Future<void> _pickInterval(BuildContext context) async {
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

  static Future<void> _pickConcurrency(BuildContext context, bool upload) async {
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

  static Future<void> _editText(
    BuildContext context, {
    required String title,
    required String hint,
    required String current,
    required Future<void> Function(String) onSave,
    bool allowClear = true,
  }) async {
    final controller = TextEditingController(text: current);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 2,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          if (allowClear)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onSave('');
              },
              child: const Text('恢复默认'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onSave(controller.text.trim());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  static Future<void> _editUploadDomain(BuildContext context) {
    final app = context.read<AppController>();
    return _editText(
      context,
      title: '上传域名',
      hint: '留空使用默认 up.woozooo.com，可带 https://',
      current: app.settings.uploadDomain,
      onSave: (value) => app.setUploadDomain(value),
    );
  }

  static Future<void> _editShareDomain(BuildContext context) {
    final app = context.read<AppController>();
    return _editText(
      context,
      title: '分享链接域名',
      hint: '留空自动尝试内置镜像，可带 https://',
      current: app.settings.shareDomain,
      onSave: (value) => app.setShareDomain(value),
    );
  }

  static Future<void> _editUserAgent(BuildContext context) {
    final app = context.read<AppController>();
    return _editText(
      context,
      title: '自定义 User-Agent',
      hint: '留空表示使用默认值',
      current: app.settings.userAgent,
      onSave: (value) => app.setUserAgent(value),
    );
  }
}

/// 高级覆盖项二级页。
class _AdvancedPage extends StatelessWidget {
  const _AdvancedPage();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return ScrollTint(
      child: Builder(
        builder: (context) {
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
                  title: const Text('高级覆盖项'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Text(
                          '仅在连接异常或域名被墙时修改，留空恢复默认',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.dns_outlined),
                              title: const Text('网盘接口域名'),
                              subtitle: Text(
                                app.settings.apiHost == 'up'
                                    ? 'up.woozooo.com'
                                    : 'pc.woozooo.com',
                              ),
                              onTap: () =>
                                  _SettingsPageState._pickApiHost(context),
                            ),
                            ListTile(
                              leading: const Icon(Icons.cloud_upload_outlined),
                              title: const Text('上传域名'),
                              subtitle: Text(
                                app.settings.uploadDomain.isEmpty
                                    ? '默认（up.woozooo.com）'
                                    : app.settings.uploadDomain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _SettingsPageState
                                  ._editUploadDomain(context),
                            ),
                            ListTile(
                              leading: const Icon(Icons.link_outlined),
                              title: const Text('分享链接域名'),
                              subtitle: Text(
                                app.settings.shareDomain.isEmpty
                                    ? '默认（自动尝试内置镜像）'
                                    : app.settings.shareDomain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () =>
                                  _SettingsPageState._editShareDomain(context),
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
                              onTap: () =>
                                  _SettingsPageState._editUserAgent(context),
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
        },
      ),
    );
  }
}
