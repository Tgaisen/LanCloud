import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/app_cache.dart';
import '../core/app_log.dart';
import '../core/app_permissions.dart';
import '../core/download_dir.dart';
import '../core/dynamic_color_support.dart';
import '../core/notifications.dart';
import '../core/platform_support.dart';
import '../core/saf_storage.dart';
import '../core/system_file_saver.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'backup_page.dart';
import 'common.dart';
import 'cookie_sheet.dart';
import 'm3e.dart';

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

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  bool _searching = false;
  bool? _notifGranted;

  /// 动态取色支持情况：进入设置页探测一次（带缓存），不放在会随
  /// 搜索 / 滚动重建的 tile 里反复查询。
  bool? _dynamicColorSupported;
  PermissionSnapshot? _permissions;

  /// 默认下载目录的真实路径（副标题里显示，进入设置时读一次）。
  String? _defaultDownloadDir;

  /// 应用专属目录的根（默认下载目录所在位置）与外部存储根：
  /// 副标题用它给下载目录分类（仅 Android）。
  List<String> _privateDirRoots = const [];
  String? _publicDirRoot;
  final TextEditingController _search = TextEditingController();

  /// 设置页列表；传给 TopBarOverlayScaffold 后点顶栏空白即可回到顶部。
  final ScrollController _list = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotifPermission();
    _refreshPermissions();
    _loadDefaultDownloadDir();
    _probeDynamicColor();
  }

  Future<void> _probeDynamicColor() async {
    final supported = await DynamicColorSupport.isSupported();
    if (mounted) setState(() => _dynamicColorSupported = supported);
  }

  Future<void> _loadDefaultDownloadDir() async {
    try {
      final path = await context.read<AppController>().defaultDownloadDirPath();
      if (PlatformSupport.isAndroid) {
        final roots = <String>{p.dirname(path)};
        try {
          roots.add((await getApplicationDocumentsDirectory()).path);
        } catch (_) {
          // 拿不到内部文档目录就少一个私有根，不影响判断
        }
        _privateDirRoots = roots.where((root) => root.isNotEmpty).toList();
        _publicDirRoot = publicStorageRootFrom(path);
      }
      if (mounted) setState(() => _defaultDownloadDir = path);
    } catch (_) {
      // 取不到路径时保持占位符，不影响设置页其余内容
    }
  }

  /// 下载目录副标题：Android 上按目录分类加前缀（私有 / 公共 / 非公共），
  /// 桌面端保持「默认（路径）」与自定义路径。
  String _downloadDirLabel(AppLocalizations l10n, AppController app) =>
      _dirLabel(l10n, app, _defaultDownloadDir);

  String _dirLabel(
    AppLocalizations l10n,
    AppController app,
    String? defaultPath,
  ) {
    final treeUri = app.settings.downloadDirTree;
    if (treeUri != null && treeUri.isNotEmpty) {
      final label = app.settings.downloadDirLabel;
      final path = (label == null || label.isEmpty) ? treeUri : label;
      return PlatformSupport.isAndroid ? l10n.customDownloadDir(path) : path;
    }
    final custom = app.settings.downloadDir;
    if (custom != null && custom.isNotEmpty) {
      if (!PlatformSupport.isAndroid) return custom;
      return switch (classifyDownloadDir(
        custom,
        privateRoots: _privateDirRoots,
        publicRoot: _publicDirRoot,
      )) {
        DownloadDirKind.privateDir => l10n.privateDownloadDir(custom),
        DownloadDirKind.publicDir => l10n.publicDownloadDir(custom),
        DownloadDirKind.customDir => l10n.customDownloadDir(custom),
      };
    }
    final path = defaultPath ?? '…';
    return PlatformSupport.isAndroid
        ? l10n.privateDownloadDir(path)
        : l10n.defaultDownloadDir(path);
  }

  /// 底栏显示项文案：首页 · 网盘 [· 传输] [· 收藏] · 我的。
  String _navItemsLabel(BuildContext context, AppController app) {
    final l10n = context.l10n;
    return [
      l10n.tabHome,
      l10n.tabDrive,
      if (app.settings.navShowTransfers) l10n.tabTransfers,
      if (app.settings.navShowFavorites) l10n.favorite,
      l10n.tabProfile,
    ].join(' · ');
  }

  /// 多选对话框：控制「传输」「收藏」是否显示在底栏。
  Future<void> _pickNavBarItems(BuildContext context) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    var transfers = app.settings.navShowTransfers;
    var favorites = app.settings.navShowFavorites;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.navBarItems),
          // M3 对话框内容边距 24dp（正文到操作区 24dp）；列表组再用自带的
          // 0 外边距铺满内容区，组沿正好落在 24dp 上
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          // 与单选弹窗同一套列表组样式：选中 = 主容器色 + 对勾（多选语义）
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 列表组比弹窗底（surfaceContainerHigh）再高一档容器色
              DialogListGroup(
                children: [
                  M3ePickTile(
                    label: l10n.tabTransfers,
                    leading: const Icon(Icons.swap_vert),
                    selected: transfers,
                    onTap: () => setDialogState(() => transfers = !transfers),
                  ),
                  M3ePickTile(
                    label: l10n.favorite,
                    leading: const Icon(Icons.star_border),
                    selected: favorites,
                    onTap: () => setDialogState(() => favorites = !favorites),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                child: Text(
                  l10n.navBarItemsHint,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await app.setNavShowTransfers(transfers);
    await app.setNavShowFavorites(favorites);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  /// 从系统设置页返回时刷新权限状态。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
      _refreshNotifPermission();
    }
  }

  Future<void> _refreshNotifPermission() async {
    final granted = await NotificationService.instance.hasPermission();
    if (mounted) setState(() => _notifGranted = granted);
  }

  Future<void> _refreshPermissions() async {
    final snapshot = await AppPermissions.instance.status();
    if (mounted) setState(() => _permissions = snapshot);
  }

  List<_Entry> _entries(AppController app) {
    final l10n = context.l10n;
    String themeModeName() => switch (app.settings.themeMode) {
      'light' => l10n.light,
      'dark' => l10n.dark,
      _ => l10n.followSystem,
    };
    String languageName() => switch (app.settings.language) {
      'zh' => l10n.chinese,
      'en' => l10n.english,
      _ => l10n.followSystem,
    };
    return [
      _Entry(
        id: 'language',
        title: l10n.language,
        subtitle: languageName(),
        keywords: const ['language', 'locale', 'zh', 'en', '语言', '中文', '英语'],
        category: 'appearance',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.translate),
          title: Text(context.l10n.language),
          subtitle: Text(languageName()),
          onTap: () => _pickLanguage(context),
        ),
      ),
      _Entry(
        id: 'theme_mode',
        title: l10n.themeMode,
        subtitle: themeModeName(),
        keywords: l10n.themeModeKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(context.l10n.themeMode),
          // MD3E：行内直接放一颗 tonal 连接式按钮组，点一下即切换
          //（按钮用短文案「系统 / 浅色 / 深色」，跟随系统只在语言弹窗里用全称）
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: M3eConnectedButtonGroup<String>(
              values: const ['system', 'light', 'dark'],
              selected: app.settings.themeMode,
              onSelected: (value) => app.setThemeMode(value),
              // 标签缩短成「系统」后回到等分宽度（占满内容区）；极窄屏下省略号兜底
              labelOf: (value) => Text(
                switch (value) {
                  'light' => context.l10n.light,
                  'dark' => context.l10n.dark,
                  _ => context.l10n.system,
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // 选中态只靠 tonal 强调色（够醒目，不再加对勾图标）
              semanticLabel: context.l10n.themeMode,
            ),
          ),
        ),
      ),
      _Entry(
        id: 'oled',
        title: l10n.oled,
        subtitle: '',
        keywords: l10n.oledKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.contrast),
          title: Text(context.l10n.oled),
          value: app.settings.oledBlack,
          onChanged: (value) => app.setOledBlack(value),
        ),
      ),
      _Entry(
        id: 'theme_seed',
        title: l10n.themeColor,
        subtitle: _seedName(context, app.settings.themeSeed),
        keywords: l10n.themeColorKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(context.l10n.themeColor),
          subtitle: Text(_seedName(context, app.settings.themeSeed)),
          trailing: CircleAvatar(
            radius: 12,
            backgroundColor: Color(app.settings.themeSeed),
          ),
          onTap: () => _pickThemeSeed(context),
        ),
      ),
      _Entry(
        id: 'dynamic_color',
        title: l10n.dynamicColor,
        subtitle: l10n.dynamicColorSubtitle,
        keywords: l10n.dynamicColorKeywords.split(' '),
        category: 'appearance',
        // Android 12+ 才有系统取色，取不到时开关置灰；支持情况在进入
        // 设置页时探测一次（DynamicColorSupport 带缓存，见其注释）
        build: (context, app) {
          // 探测期间按「支持」处理：开关直接反映设置值，不会先显示关闭
          // 再跳到打开（开着动态取色的设备打开设置页会闪一下）；
          // 探测结果确实不支持时再置灰并显示不支持文案
          final supported = _dynamicColorSupported ?? true;
          return SwitchListTile(
            secondary: const Icon(Icons.wallpaper_outlined),
            title: Text(context.l10n.dynamicColor),
            subtitle: Text(
              supported
                  ? context.l10n.dynamicColorSubtitle
                  : context.l10n.dynamicColorUnsupported,
            ),
            value: supported && app.settings.dynamicColor,
            onChanged: supported ? (value) => app.setDynamicColor(value) : null,
          );
        },
      ),
      _Entry(
        id: 'hide_top_bar',
        title: l10n.hideTopBar,
        subtitle: l10n.hideTopBarSubtitle,
        keywords: l10n.hideTopBarKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.vertical_align_top),
          title: Text(context.l10n.hideTopBar),
          subtitle: Text(context.l10n.hideTopBarSubtitle),
          value: app.settings.hideTopBar,
          onChanged: (value) => app.setHideTopBar(value),
        ),
      ),
      _Entry(
        id: 'hide_bottom_bar',
        title: l10n.hideBottomBar,
        subtitle: l10n.hideBottomBarSubtitle,
        keywords: l10n.hideBottomBarKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.vertical_align_bottom),
          title: Text(context.l10n.hideBottomBar),
          subtitle: Text(context.l10n.hideBottomBarSubtitle),
          value: app.settings.hideBottomBar,
          onChanged: (value) => app.setHideBottomBar(value),
        ),
      ),
      _Entry(
        id: 'floating_nav',
        title: l10n.floatingNav,
        subtitle: '',
        keywords: l10n.floatingNavKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.smart_button),
          title: Text(context.l10n.floatingNav),
          value: app.settings.floatingNavBar,
          onChanged: (value) => app.setFloatingNavBar(value),
        ),
      ),
      _Entry(
        id: 'nav_items',
        title: l10n.navBarItems,
        subtitle: _navItemsLabel(context, app),
        keywords: l10n.navBarItemsKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.bottom_navigation),
          title: Text(context.l10n.navBarItems),
          subtitle: Text(_navItemsLabel(context, app)),
          onTap: () => _pickNavBarItems(context),
        ),
      ),
      _Entry(
        id: 'swipe_tabs',
        title: l10n.swipeTabs,
        subtitle: l10n.swipeTabsSubtitle,
        keywords: l10n.swipeTabsKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.swipe),
          title: Text(context.l10n.swipeTabs),
          subtitle: Text(context.l10n.swipeTabsSubtitle),
          value: app.settings.swipeTabs,
          onChanged: (value) => app.setSwipeTabs(value),
        ),
      ),
      _Entry(
        id: 'transition_animations',
        title: l10n.transitionAnimations,
        subtitle: l10n.transitionAnimationsSubtitle,
        keywords: l10n.transitionAnimationsKeywords.split(' '),
        category: 'appearance',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.animation),
          title: Text(context.l10n.transitionAnimations),
          subtitle: Text(context.l10n.transitionAnimationsSubtitle),
          value: app.settings.transitionAnimations,
          onChanged: (value) => app.setTransitionAnimations(value),
        ),
      ),
      _Entry(
        id: 'download_dir',
        title: l10n.downloadDir,
        subtitle: _downloadDirLabel(l10n, app),
        keywords: l10n.downloadDirKeywords.split(' '),
        category: 'behavior',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(context.l10n.downloadDir),
          subtitle: Text(
            _downloadDirLabel(context.l10n, app),
            // 默认目录会带上真实路径，比较长：允许换行显示完整路径
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _changeDownloadDir(context),
        ),
      ),
      _Entry(
        id: 'launch_page',
        title: l10n.launchPage,
        subtitle: app.settings.launchPage == 'drive'
            ? l10n.tabDrive
            : l10n.tabHome,
        keywords: l10n.launchPageKeywords.split(' '),
        category: 'behavior',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(context.l10n.launchPage),
          subtitle: Text(
            app.settings.launchPage == 'drive'
                ? context.l10n.tabDrive
                : context.l10n.tabHome,
          ),
          onTap: () => _pickLaunchPage(context),
        ),
      ),
      _Entry(
        id: 'home_folder_open',
        title: l10n.homeFolderOpen,
        subtitle: app.settings.homeFolderOpenMode == 'drive'
            ? l10n.openInDriveTab
            : l10n.openInNewPage,
        keywords: l10n.homeFolderOpenKeywords.split(' '),
        category: 'behavior',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.open_in_new),
          title: Text(context.l10n.homeFolderOpen),
          subtitle: Text(
            app.settings.homeFolderOpenMode == 'drive'
                ? context.l10n.openInDriveTab
                : context.l10n.openInNewPage,
          ),
          onTap: () => _pickHomeFolderOpenMode(context),
        ),
      ),
      _Entry(
        id: 'cache_folders',
        title: l10n.cacheFolders,
        subtitle: l10n.cacheFoldersSubtitle,
        keywords: l10n.cacheFoldersKeywords.split(' '),
        category: 'behavior',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.cached_outlined),
          title: Text(context.l10n.cacheFolders),
          subtitle: Text(context.l10n.cacheFoldersSubtitle),
          value: app.settings.cacheFolders,
          onChanged: (value) => app.setCacheFolders(value),
        ),
      ),
      _Entry(
        id: 'load_all_pages',
        title: l10n.loadAllPages,
        subtitle: l10n.loadAllPagesSubtitle,
        keywords: l10n.loadAllPagesKeywords.split(' '),
        category: 'behavior',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.download_for_offline_outlined),
          title: Text(context.l10n.loadAllPages),
          subtitle: Text(context.l10n.loadAllPagesSubtitle),
          value: app.settings.loadAllPages,
          onChanged: (value) => app.setLoadAllPages(value),
        ),
      ),
      _Entry(
        id: 'notify_progress',
        title: l10n.notifProgress,
        subtitle: l10n.notifProgressSubtitle,
        keywords: l10n.notifProgressKeywords.split(' '),
        category: 'notifications',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.speed),
          title: Text(context.l10n.notifProgress),
          subtitle: Text(context.l10n.notifProgressSubtitle),
          value: app.settings.notifyProgress,
          onChanged: _setNotifyProgress,
        ),
      ),
      _Entry(
        id: 'notify_done',
        title: l10n.notifDone,
        subtitle: l10n.notifDoneSubtitle,
        keywords: l10n.notifDoneKeywords.split(' '),
        category: 'notifications',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.task_alt),
          title: Text(context.l10n.notifDone),
          subtitle: Text(context.l10n.notifDoneSubtitle),
          value: app.settings.notifyDone,
          onChanged: _setNotifyDone,
        ),
      ),
      _Entry(
        id: 'clipboard_link',
        title: l10n.clipboardLinkPrompt,
        subtitle: l10n.clipboardLinkPromptSubtitle,
        keywords: l10n.clipboardLinkPromptKeywords.split(' '),
        category: 'notifications',
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.content_paste_go),
          title: Text(context.l10n.clipboardLinkPrompt),
          subtitle: Text(context.l10n.clipboardLinkPromptSubtitle),
          value: app.settings.clipboardLinkPrompt,
          onChanged: (value) => app.setClipboardLinkPrompt(value),
        ),
      ),
      // 三项系统权限（通知 / 安装应用 / 忽略电池优化）收进一个弹窗，
      // 设置页只留一个「管理权限」入口
      _Entry(
        id: 'manage_permissions',
        title: l10n.managePermissions,
        subtitle: l10n.managePermissionsSubtitle,
        keywords: [
          ...l10n.managePermissionsKeywords.split(' '),
          ...l10n.permissionInstallKeywords.split(' '),
          ...l10n.permissionBatteryKeywords.split(' '),
          ...l10n.notifPermissionKeywords.split(' '),
        ],
        category: 'permissions',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.shield),
          title: Text(context.l10n.managePermissions),
          subtitle: Text(context.l10n.managePermissionsSubtitle),
          onTap: () => _showManagePermissions(context),
        ),
      ),
      _Entry(
        id: 'default_links',
        title: l10n.manageDefaultLinks,
        subtitle: l10n.manageDefaultLinksSubtitle,
        keywords: l10n.manageDefaultLinksKeywords.split(' '),
        category: 'permissions',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.link_outlined),
          title: Text(context.l10n.manageDefaultLinks),
          subtitle: Text(context.l10n.manageDefaultLinksSubtitle),
          onTap: _openDefaultLinkSettings,
        ),
      ),
      _Entry(
        id: 'app_settings',
        title: l10n.openSystemSettings,
        subtitle: '',
        keywords: l10n.openSystemSettingsKeywords.split(' '),
        category: 'permissions',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.page_info),
          title: Text(context.l10n.openSystemSettings),
          onTap: _openAppSettings,
        ),
      ),
      _Entry(
        id: 'interval',
        title: l10n.requestInterval,
        subtitle: l10n.requestIntervalSubtitle(app.settings.requestInterval),
        keywords: l10n.requestIntervalKeywords.split(' '),
        category: 'connection',
        build: (context, app) => _SliderTile<int>(
          icon: Icons.timer_outlined,
          title: context.l10n.requestInterval,
          // 离散档位 = slider 的 stops（M3E：有预设值时手柄吸附到最近的档）
          values: const [25, 50, 75, 100, 150, 200, 300, 500, 1000],
          current: app.settings.requestInterval,
          labelOf: (ms) => '$ms ms',
          onChanged: app.setRequestInterval,
        ),
      ),
      _Entry(
        id: 'max_uploads',
        title: l10n.maxUploads,
        subtitle: '${app.settings.maxUploads}',
        keywords: l10n.uploadKeywords.split(' '),
        category: 'connection',
        build: (context, app) => _SliderTile<int>(
          icon: Icons.upload_outlined,
          title: context.l10n.maxUploads,
          values: const [1, 2, 3],
          current: app.settings.maxUploads,
          labelOf: (value) => '$value',
          onChanged: app.setMaxUploads,
        ),
      ),
      _Entry(
        id: 'max_downloads',
        title: l10n.maxDownloads,
        subtitle: '${app.settings.maxDownloads}',
        keywords: l10n.downloadKeywords.split(' '),
        category: 'connection',
        build: (context, app) => _SliderTile<int>(
          icon: Icons.download_outlined,
          title: context.l10n.maxDownloads,
          values: const [1, 2, 3, 4, 5],
          current: app.settings.maxDownloads,
          labelOf: (value) => '$value',
          onChanged: app.setMaxDownloads,
        ),
      ),
      _Entry(
        id: 'api_host',
        title: l10n.apiHost,
        subtitle: app.settings.apiHost == 'up'
            ? 'up.woozooo.com'
            : 'pc.woozooo.com',
        keywords: l10n.apiHostKeywords.split(' '),
        category: 'advanced',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(context.l10n.apiHost),
          subtitle: Text(
            app.settings.apiHost == 'up' ? 'up.woozooo.com' : 'pc.woozooo.com',
          ),
          onTap: () => _pickApiHost(context),
        ),
      ),
      _Entry(
        id: 'upload_path',
        title: l10n.uploadPath,
        subtitle: app.settings.uploadPath,
        keywords: l10n.uploadPathKeywords.split(' '),
        category: 'advanced',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text(context.l10n.uploadPath),
          subtitle: Text(
            app.settings.uploadPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _pickUploadPath(context),
        ),
      ),
      _Entry(
        id: 'user_agent',
        title: l10n.userAgent,
        subtitle: app.settings.userAgent.isEmpty
            ? l10n.defaultUserAgent
            : app.settings.userAgent,
        keywords: l10n.userAgentKeywords.split(' '),
        category: 'advanced',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(context.l10n.userAgent),
          subtitle: Text(
            app.settings.userAgent.isEmpty
                ? context.l10n.defaultUserAgent
                : app.settings.userAgent,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _editUserAgent(context),
        ),
      ),
      _Entry(
        id: 'backup',
        title: l10n.backupAndRestore,
        subtitle: l10n.backupAndRestoreSubtitle,
        keywords: l10n.backupKeywords.split(' '),
        category: 'data',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.sync),
          title: Text(context.l10n.backupAndRestore),
          subtitle: Text(context.l10n.backupAndRestoreSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const BackupPage())),
        ),
      ),
      _Entry(
        id: 'recent_limit',
        title: l10n.recentLimit,
        subtitle: app.settings.recentLimit <= 0
            ? l10n.recentLimitOff
            : l10n.recentLimitValue(app.settings.recentLimit),
        keywords: l10n.recentLimitKeywords.split(' '),
        category: 'data',
        build: (context, app) => _SliderTile<int>(
          icon: Icons.history,
          title: context.l10n.recentLimit,
          // 0 = 不记录（l10n.recentLimitOff）
          values: const [0, 10, 50, 100, 200],
          current: app.settings.recentLimit,
          labelOf: (value) => value <= 0
              ? context.l10n.recentLimitOff
              : context.l10n.recentLimitValue(value),
          onChanged: app.setRecentLimit,
        ),
      ),
      _Entry(
        id: 'clear_recents',
        title: l10n.clearRecents,
        subtitle: '',
        keywords: l10n.clearRecentsKeywords.split(' '),
        category: 'data',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.delete_sweep_outlined),
          title: Text(context.l10n.clearRecents),
          onTap: () async {
            await app.db.clearRecents(app.activeUid ?? '');
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(context.l10n.cleared)));
            }
          },
        ),
      ),
      _Entry(
        id: 'clear_cache',
        title: l10n.clearCache,
        subtitle: l10n.clearCacheSubtitle,
        keywords: l10n.clearCacheKeywords.split(' '),
        category: 'data',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(context.l10n.clearCache),
          onTap: () => _clearCache(context),
        ),
      ),
      _Entry(
        id: 'show_cookie',
        title: l10n.showCookie,
        subtitle: l10n.showCookieSubtitle,
        keywords: l10n.showCookieKeywords.split(' '),
        category: 'privacy',
        build: (context, app) {
          final account = app.activeAccount;
          return ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(context.l10n.showCookie),
            subtitle: Text(context.l10n.showCookieSubtitle),
            enabled: account != null,
            onTap: account == null
                ? null
                : () => showCookieFlow(context, account),
          );
        },
      ),
      _Entry(
        id: 'export_logs',
        title: l10n.exportLogs,
        subtitle: l10n.exportLogsSubtitle,
        keywords: l10n.exportLogsKeywords.split(' '),
        category: 'privacy',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.article_outlined),
          title: Text(context.l10n.exportLogs),
          subtitle: Text(context.l10n.exportLogsSubtitle),
          onTap: () => _exportLogs(context),
        ),
      ),
    ]..removeWhere(
      // 权限 / 安装 / 默认链接是 Android 原生通道的能力，动态取色只有
      // Android 12+ 有，这些在桌面端都直接不显示。
      (entry) =>
          !PlatformSupport.isMobile && _androidOnlyEntries.contains(entry.id),
    );
  }

  /// 只有 Android 才有对应实现的设置项。
  static const _androidOnlyEntries = {
    'dynamic_color',
    'manage_permissions',
    'default_links',
    'app_settings',
  };

  String _seedName(BuildContext context, int seed) => switch (seed) {
    0xFF2E6BE6 => context.l10n.classicBlue,
    0xFF00897B => context.l10n.teal,
    0xFF7B4DFF => context.l10n.violet,
    0xFFE5533D => context.l10n.vermilion,
    0xFF3F7D20 => context.l10n.olive,
    0xFF6750A4 => context.l10n.colorMd3Purple,
    0xFF0B57D0 => context.l10n.colorRoyalBlue,
    0xFF984061 => context.l10n.colorRose,
    0xFF8B5000 => context.l10n.colorAmber,
    _ => context.l10n.custom,
  };

  /// 退出搜索：清空关键词并切回分类列表（与收藏页同一套行为）。
  void _exitSearch() {
    setState(() {
      _searching = false;
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final entries = _entries(app);
    final query = _search.text.trim().toLowerCase();

    final matching = entries
        .where(
          (e) =>
              e.title.toLowerCase().contains(query) ||
              e.subtitle.toLowerCase().contains(query) ||
              _categoryName(e.category).toLowerCase().contains(query) ||
              e.keywords.any((k) => k.toLowerCase().contains(query)),
        )
        .toList();

    return PopScope(
      // 搜索时返回先退出搜索（与收藏页一致），再退出页面
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searching) _exitSearch();
      },
      child: TopBarOverlayScaffold(
        controller: _list,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          // 搜索时「关闭搜索」占用返回按钮的位置（与收藏页一致）
          leading: _searching
              ? IconButton(
                  tooltip: l10n.closeSearch,
                  icon: const Icon(Icons.close),
                  onPressed: _exitSearch,
                )
              : const AppBarBackButton(),
          // 标题 ↔ 搜索框带显示 / 隐藏动画，不要直接闪出来
          title: AppBarSearchSwitcher(
            searching: _searching,
            title: Text(l10n.settings),
            searchField: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.searchSettings,
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          actions: _searching
              ? const <Widget>[]
              : [
                  IconButton(
                    tooltip: l10n.searchSettings,
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => _searching = true),
                  ),
                ],
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            // 整块布局：分组高度差异大，懒布局会让 maxScrollExtent 一直修正、
            // 滚动条滑块长度抖动（见 SliverColumn 注释）
            // 整块布局：分组高度差异大，懒布局会让 maxScrollExtent 一直修正、
            // 滚动条滑块长度抖动（见 SliverColumn 注释）
            sliver: SliverColumn(
              children: _searching
                  ? _buildSearchResults(context, app, matching)
                  : _buildCategories(context, app, entries),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategories(
    BuildContext context,
    AppController app,
    List<_Entry> entries,
  ) {
    final l10n = context.l10n;
    final groups = <String, List<_Entry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.category, () => []).add(e);
    }
    // 分组显示顺序：与条目声明顺序无关。「权限」使用频率低，排在最后。
    const order = [
      'appearance',
      'behavior',
      'notifications',
      'connection',
      'advanced',
      'data',
      'privacy',
      'permissions',
    ];
    final names = [
      ...order.where(groups.containsKey),
      ...groups.keys.where((name) => !order.contains(name)),
    ];
    final widgets = <Widget>[];
    for (final name in names) {
      if (name == 'advanced') {
        widgets
          ..add(M3eSectionHeader(l10n.categoryAdvanced))
          ..add(
            SegmentedList(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.advanced),
                  subtitle: Text(l10n.advancedSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const _AdvancedPage()),
                  ),
                ),
              ],
            ),
          );
        continue;
      }
      widgets
        ..add(M3eSectionHeader(_categoryName(name)))
        ..add(
          SegmentedList(
            children: [
              for (final entry in groups[name]!) entry.build(context, app),
            ],
          ),
        );
    }
    return widgets;
  }

  String _categoryName(String id) => switch (id) {
    'appearance' => context.l10n.categoryAppearance,
    'behavior' => context.l10n.categoryBehavior,
    'notifications' => context.l10n.notifications,
    'permissions' => context.l10n.categoryPermissions,
    'privacy' => context.l10n.categoryPrivacy,
    'connection' => context.l10n.categoryConnection,
    'advanced' => context.l10n.categoryAdvanced,
    'data' => context.l10n.categoryData,
    _ => id,
  };

  String _installStatusText() => switch (_permissions?.install) {
    PermissionState.granted => context.l10n.permissionInstallGranted,
    PermissionState.denied => context.l10n.permissionInstallDenied,
    _ => context.l10n.permissionChecking,
  };

  String _batteryStatusText() => switch (_permissions?.battery) {
    PermissionState.granted => context.l10n.permissionBatteryGranted,
    PermissionState.denied => context.l10n.permissionBatteryRestricted,
    _ => context.l10n.permissionChecking,
  };

  Future<void> _openInstallSettings() async {
    final l10n = context.l10n;
    final ok = await AppPermissions.instance.openInstallSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.permissionOpenFailed)));
    }
  }

  /// 打开系统的「默认打开链接」设置页（Android 12+）。
  Future<void> _openDefaultLinkSettings() async {
    final l10n = context.l10n;
    final ok = await AppPermissions.instance.openDefaultLinkSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.permissionOpenFailed)));
    }
  }

  /// 打开系统设置里的本应用信息页。
  Future<void> _openAppSettings() async {
    final l10n = context.l10n;
    final ok = await AppPermissions.instance.openAppSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.permissionOpenFailed)));
    }
  }

  /// 导出运行日志：合并本机日志，交给系统「保存文件」对话框。
  Future<void> _exportLogs(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await AppLog.instance.exportBundle();
      if (!mounted) return;
      if (file == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.exportLogsEmpty)));
        return;
      }
      final saved = await SystemFileSaver.save(
        sourcePath: file.path,
        fileName: p.basename(file.path),
        mime: 'text/plain',
      );
      if (!mounted || saved == null) return; // 用户取消保存
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.exportLogsSaved(saved))),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.exportLogsFailed)));
      }
    }
  }

  /// 「清理缓存」：临时文件（拖拽 / 选文件 / 拍照副本、备份与日志导出残留、
  /// 网页缓存）+ 图片缓存 + 网盘目录列表缓存。账号、设置和已下载的文件不受影响。
  Future<void> _clearCache(BuildContext context) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    // 统计缓存大小要遍历整个缓存目录（Windows 上可能要好几秒）：先转圈再弹确认框
    showLoadingDialog(context, l10n.loading);
    int? size;
    try {
      size = await AppCache.size();
    } finally {
      navigator.pop();
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.clearCache),
        content: Text(
          size == null
              ? dialogContext.l10n.clearCacheBodyUnknown
              : dialogContext.l10n.clearCacheBody(formatBytes(size)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.clean),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // 清理同样要遍历目录：这段等待弹窗写「清理中…」
    showLoadingDialog(context, l10n.cleaning);
    int? freed;
    try {
      freed = await AppCache.clear();
      // 图片缓存（内存）与网盘目录列表缓存也一起清掉
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      app.driveCache.clear();
    } finally {
      // 出啥岔子都要把等待弹窗收掉，别把用户卡在转圈里
      navigator.pop();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.cacheCleared(formatBytes(freed ?? 0))),
      ),
    );
  }

  Future<void> _requestBatteryOptimization() async {
    final l10n = context.l10n;
    final ok = await AppPermissions.instance.requestBattery();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.permissionOpenFailed)));
    }
  }

  Future<void> _setNotifyProgress(bool value) async {
    final app = context.read<AppController>();
    if (value) {
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      final granted = await NotificationService.instance.requestPermission();
      if (mounted) setState(() => _notifGranted = granted);
      if (!granted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.notifPermissionDeniedHint)),
        );
      }
    }
    await app.setNotifyProgress(value);
  }

  Future<void> _setNotifyDone(bool value) async {
    final app = context.read<AppController>();
    if (value) {
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      final granted = await NotificationService.instance.requestPermission();
      if (mounted) setState(() => _notifGranted = granted);
      if (!granted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.notifPermissionDeniedHint)),
        );
      }
    }
    await app.setNotifyDone(value);
  }

  Future<void> _requestNotifPermission() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final granted = await NotificationService.instance.requestPermission();
    if (mounted) setState(() => _notifGranted = granted);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? l10n.notifPermissionGranted
              : l10n.notifPermissionDeniedHint,
        ),
      ),
    );
  }

  /// 「管理权限」弹窗：通知 / 安装应用 / 忽略电池优化三项系统权限。
  /// 样式与「识别二维码」弹窗一致（标题 + 分组列表），只有 Android 会用到。
  Future<void> _showManagePermissions(BuildContext context) {
    final l10n = context.l10n;
    final notifStatus = _notifGranted == null
        ? l10n.notifPermissionChecking
        : (_notifGranted!
              ? l10n.notifPermissionGranted
              : l10n.notifPermissionDenied);
    return showAppSheet<void>(
      context,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.managePermissions,
                style: context.m3eEmphasizedTheme.titleLarge,
              ),
            ),
            SheetListGroup(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.notifPermission),
                  subtitle: Text(notifStatus),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    _requestNotifPermission();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.install_mobile),
                  title: Text(l10n.permissionInstall),
                  subtitle: Text(_installStatusText()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openInstallSettings();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.battery_0_bar),
                  title: Text(l10n.permissionBattery),
                  subtitle: Text(_batteryStatusText()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    _requestBatteryOptimization();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSearchResults(
    BuildContext context,
    AppController app,
    List<_Entry> matching,
  ) {
    if (_search.text.trim().isEmpty) {
      return [
        const SizedBox(height: 48),
        Center(child: Text(context.l10n.searchPlaceholder)),
      ];
    }
    if (matching.isEmpty) {
      return [
        const SizedBox(height: 48),
        Center(child: Text(context.l10n.noMatch)),
      ];
    }
    return [
      SegmentedList(
        children: [for (final entry in matching) entry.build(context, app)],
      ),
    ];
  }

  Future<void> _changeDownloadDir(BuildContext context) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    // 当前目录：与副标题同一套分类（私有 / 公共 / 非公共）
    var defaultPath = _defaultDownloadDir;
    if (defaultPath == null) {
      try {
        defaultPath = await app.defaultDownloadDirPath();
      } catch (_) {
        // 取不到默认路径时用占位符，不影响弹窗其它信息
      }
    }
    final current = _dirLabel(l10n, app, defaultPath);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.downloadDir),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(current),
            if (PlatformSupport.isAndroid) ...[
              const SizedBox(height: 12),
              Text(
                l10n.downloadDirHint,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await app.setDownloadDir(null);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.restoredDefaultDir)),
                );
              }
            },
            child: Text(l10n.restoreDefault),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                if (PlatformSupport.isAndroid) {
                  // Android：公共目录（Download、Documents 等）直接按路径
                  // 写入；其它目录走 SAF 目录授权
                  final dir = await SafStorage.pickDirectory(
                    initialUri: app.settings.downloadDirTree,
                  );
                  if (dir == null) return; // 用户取消
                  final direct = dir.directPath;
                  if (direct != null) {
                    await app.setDownloadDir(direct);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.downloadDirSet(direct))),
                      );
                    }
                    return;
                  }
                  await app.setSafDownloadDir(dir);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.downloadDirSet(dir.label))),
                    );
                  }
                  return;
                }
                final dir = await FilePicker.platform.getDirectoryPath();
                if (dir != null && dir.isNotEmpty) {
                  await app.setDownloadDir(dir);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.downloadDirSet(dir))),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  final message = e is PlatformException
                      ? (e.message ?? e.code)
                      : '$e';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.pickDirFailed(message))),
                  );
                }
              }
            },
            child: Text(l10n.change),
          ),
        ],
      ),
    );
  }

  /// MD3E 单选弹窗：连接式列表组（组内 2dp 间隔 + 外侧 16 / 组内 4 圆角），
  /// 选中项填主容器色 + 尾部对勾。
  ///
  /// **参考 M3 规范**：选中项用 primary container / on primary container 一对
  /// 角色，并且「选中不能只靠颜色」——底色之外再加对勾；语义上整项是一个
  /// 单选项（checked + 互斥组）。
  static Future<void> _pickRadio<T>(
    BuildContext context, {
    required String title,
    required List<(T, String)> options,
    required T current,
    required Future<void> Function(T) onSelect,
    String? message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        // M3 对话框内容边距 24dp；列表组自带 0 外边距，组沿正好落在 24dp 上
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Text(
                    message,
                    style: Theme.of(dialogContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ),
              // 比弹窗底（surfaceContainerHigh）再高一档容器色
              DialogListGroup(
                children: [
                  for (final entry in options)
                    M3ePickTile(
                      label: entry.$2,
                      selected: current == entry.$1,
                      singleSelect: true,
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        await onSelect(entry.$1);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _pickLaunchPage(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _pickRadio(
      context,
      title: l10n.launchPage,
      options: [('home', l10n.tabHome), ('drive', l10n.tabDrive)],
      current: app.settings.launchPage,
      onSelect: (value) => app.setLaunchPage(value),
    );
  }

  static Future<void> _pickHomeFolderOpenMode(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _pickRadio(
      context,
      title: l10n.homeFolderOpen,
      // 网盘页作为首项与默认值
      options: [('drive', l10n.openInDriveTab), ('page', l10n.openInNewPage)],
      current: app.settings.homeFolderOpenMode,
      onSelect: (value) => app.setHomeFolderOpenMode(value),
    );
  }

  static Future<void> _pickLanguage(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _pickRadio(
      context,
      title: l10n.language,
      options: [
        ('system', l10n.followSystem),
        ('zh', l10n.chinese),
        ('en', l10n.english),
      ],
      current: app.settings.language,
      onSelect: (value) => app.setLanguage(value),
    );
  }

  static Future<void> _pickApiHost(BuildContext context) {
    final app = context.read<AppController>();
    return _pickRadio(
      context,
      title: context.l10n.apiHost,
      options: const [('pc', 'pc.woozooo.com'), ('up', 'up.woozooo.com')],
      current: app.settings.apiHost,
      onSelect: (value) => app.setApiHost(value),
    );
  }

  static Future<void> _pickThemeSeed(BuildContext context) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    final presets = <int, String>{
      0xFF2E6BE6: l10n.classicBlue,
      0xFF00897B: l10n.teal,
      0xFF7B4DFF: l10n.violet,
      0xFFE5533D: l10n.vermilion,
      0xFF3F7D20: l10n.olive,
      // MD3 官方基准色（Material 3 baseline）与经典 Material 色板补充
      0xFF6750A4: l10n.colorMd3Purple,
      0xFF0B57D0: l10n.colorRoyalBlue,
      0xFF984061: l10n.colorRose,
      0xFF8B5000: l10n.colorAmber,
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.themeColor),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                child: Text(
                  l10n.themeSeedDynamicHint,
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // 与其它选择弹窗同一套列表组样式：选中 = 主容器色 + 对勾
              // 比弹窗底（surfaceContainerHigh）再高一档容器色
              DialogListGroup(
                children: [
                  for (final entry in presets.entries)
                    M3ePickTile(
                      label: entry.value,
                      selected: app.settings.themeSeed == entry.key,
                      singleSelect: true,
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: Color(entry.key),
                      ),
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        await app.setThemeSeed(entry.key);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
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
      builder: (dialogContext) => formDialog(
        dialogContext,
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
              child: Text(context.l10n.restoreDefault),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onSave(controller.text.trim());
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  static Future<void> _pickUploadPath(BuildContext context) {
    final app = context.read<AppController>();
    return _pickRadio(
      context,
      title: context.l10n.uploadPath,
      message: context.l10n.uploadPathHint,
      options: const [
        ('html5up.php', 'html5up.php'),
        ('fileup.php', 'fileup.php'),
      ],
      current: app.settings.uploadPath,
      onSelect: (value) => app.setUploadPath(value),
    );
  }

  static Future<void> _editUserAgent(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _editText(
      context,
      title: l10n.userAgent,
      hint: l10n.userAgentHint,
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
    final l10n = context.l10n;
    return TopBarOverlayScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(l10n.advanced),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverColumn(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  l10n.advancedHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              SegmentedList(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(l10n.apiHost),
                    subtitle: Text(
                      app.settings.apiHost == 'up'
                          ? 'up.woozooo.com'
                          : 'pc.woozooo.com',
                    ),
                    onTap: () => _SettingsPageState._pickApiHost(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: Text(l10n.uploadPath),
                    subtitle: Text(
                      app.settings.uploadPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _SettingsPageState._pickUploadPath(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(l10n.userAgent),
                    subtitle: Text(
                      app.settings.userAgent.isEmpty
                          ? l10n.defaultUserAgent
                          : app.settings.userAgent,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _SettingsPageState._editUserAgent(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// MD3E 设置项滑杆：图标 + 标题 + 尾部当前值，下面一行滑杆。
///
/// **参考 M3 规范**：[M3ESlider]（XS 档：16dp 轨道 / 44dp 手柄、手柄按下变窄）
/// 采用 stops 配置——[values] 就是全部可取值，手柄吸附到最近的档；
/// 数值显示在行的 trailing text 位（「值显示在别处时不必再用浮动值标记」）。
/// 滑杆放在 ListTile 的 subtitle 槽里，自动让开左侧图标、和标题左对齐。
///
/// **本应用的设计决定（非 M3 规范）**：拖动时只更新本地显示，松手才写设置
/// （避免拖动过程中反复落盘）。
class _SliderTile<T> extends StatefulWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final String title;

  /// 全部可取值（顺序即滑杆从左到右的档位）。
  final List<T> values;
  final T current;

  /// 当前值的显示文本（尾部 + 无障碍）。
  final String Function(T value) labelOf;

  /// 松手后落盘。
  final ValueChanged<T> onChanged;

  @override
  State<_SliderTile<T>> createState() => _SliderTileState<T>();
}

class _SliderTileState<T> extends State<_SliderTile<T>> {
  late int _index = _indexOf(widget.current);

  int _indexOf(T value) {
    final index = widget.values.indexOf(value);
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant _SliderTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改了值（备份恢复、重置等）时跟上
    if (widget.current != oldWidget.current) {
      _index = _indexOf(widget.current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.values[_index];
    return ListTile(
      leading: Icon(widget.icon),
      title: Text(widget.title),
      // 当前值放尾部（列表的 trailing text 角色），拖动时跟着变
      trailing: Text(
        widget.labelOf(value),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4, right: 8),
        child: Semantics(
          label: widget.title,
          child: M3ESlider(
            value: _index.toDouble(),
            min: 0,
            max: (widget.values.length - 1).toDouble(),
            divisions: widget.values.length - 1,
            onChanged: (v) => setState(() => _index = v.round()),
            // 松手才落盘；用本地档位（拖动中同步更新）而不是回调给的数值：
            // 事件成批到达时，受控的 widget.value 可能还停在上一帧
            onChangeEnd: (_) => _commit(),
          ),
        ),
      ),
    );
  }

  /// 落盘：值没变就不写（点一下没拖动、拖回原档位都不写）。
  void _commit() {
    final value = widget.values[_index];
    if (value != widget.current) widget.onChanged(value);
  }
}
