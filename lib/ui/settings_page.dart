import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Icons;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:provider/provider.dart';

import '../core/app_controller.dart';
import '../core/app_log.dart';
import '../core/app_permissions.dart';
import '../core/notifications.dart';
import '../core/system_share.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'backup_page.dart';
import 'common.dart';
import 'cookie_sheet.dart';
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

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  bool _searching = false;
  bool? _notifGranted;
  PermissionSnapshot? _permissions;
  /// 默认下载目录的真实路径（副标题里显示，进入设置时读一次）。
  String? _defaultDownloadDir;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotifPermission();
    _refreshPermissions();
    _loadDefaultDownloadDir();
  }

  Future<void> _loadDefaultDownloadDir() async {
    try {
      final path =
          await context.read<AppController>().defaultDownloadDirPath();
      if (mounted) setState(() => _defaultDownloadDir = path);
    } catch (_) {
      // 取不到路径时保持占位符，不影响设置页其余内容
    }
  }

  /// 下载目录副标题：自定义目录显示所选路径，默认目录显示真实路径。
  String _downloadDirLabel(AppLocalizations l10n, AppController app) {
    final custom = app.settings.downloadDir;
    if (custom != null && custom.isNotEmpty) return custom;
    final path = _defaultDownloadDir;
    return l10n.defaultDownloadDir(path ?? '…');
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
          // 左右不留内边距：选项整行显示，波纹不会被截断
          contentPadding: const EdgeInsets.only(top: 8, bottom: 4),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                secondary: const Icon(Icons.swap_vert),
                title: Text(l10n.tabTransfers),
                value: transfers,
                onChanged: (value) =>
                    setDialogState(() => transfers = value ?? false),
              ),
              CheckboxListTile(
                secondary: const Icon(Icons.star_border),
                title: Text(l10n.favorite),
                value: favorites,
                onChanged: (value) =>
                    setDialogState(() => favorites = value ?? false),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
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
          subtitle: Text(themeModeName()),
          onTap: () => _pickThemeMode(context),
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
        // Android 12+ 才有系统取色，取不到时开关置灰
        build: (context, app) => DynamicColorBuilder(
          builder: (light, dark) {
            final supported = light != null || dark != null;
            return SwitchListTile(
              secondary: const Icon(Icons.wallpaper_outlined),
              title: Text(context.l10n.dynamicColor),
              subtitle: Text(
                supported
                    ? context.l10n.dynamicColorSubtitle
                    : context.l10n.dynamicColorUnsupported,
              ),
              value: supported && app.settings.dynamicColor,
              onChanged:
                  supported ? (value) => app.setDynamicColor(value) : null,
            );
          },
        ),
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
        subtitle: app.settings.launchPage == 'drive' ? l10n.tabDrive : l10n.tabHome,
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
      _Entry(
        id: 'notify_permission',
        title: l10n.notifPermission,
        subtitle: _notifGranted == null
            ? l10n.notifPermissionChecking
            : (_notifGranted!
                ? l10n.notifPermissionGranted
                : l10n.notifPermissionDenied),
        keywords: l10n.notifPermissionKeywords.split(' '),
        category: 'notifications',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: Text(context.l10n.notifPermission),
          subtitle: Text(
            _notifGranted == null
                ? context.l10n.notifPermissionChecking
                : (_notifGranted!
                    ? context.l10n.notifPermissionGranted
                    : context.l10n.notifPermissionDenied),
          ),
          onTap: _requestNotifPermission,
        ),
      ),
      _Entry(
        id: 'camera_permission',
        title: l10n.permissionCamera,
        subtitle: _cameraStatusText(),
        keywords: l10n.permissionCameraKeywords.split(' '),
        category: 'permissions',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.qr_code),
          title: Text(context.l10n.permissionCamera),
          subtitle: Text(_cameraStatusText()),
          onTap: _requestCameraPermission,
        ),
      ),
      _Entry(
        id: 'install_permission',
        title: l10n.permissionInstall,
        subtitle: _installStatusText(),
        keywords: l10n.permissionInstallKeywords.split(' '),
        category: 'permissions',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.install_mobile),
          title: Text(context.l10n.permissionInstall),
          subtitle: Text(_installStatusText()),
          onTap: _openInstallSettings,
        ),
      ),
      _Entry(
        id: 'battery_permission',
        title: l10n.permissionBattery,
        subtitle: _batteryStatusText(),
        keywords: l10n.permissionBatteryKeywords.split(' '),
        category: 'permissions',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.battery_alert_outlined),
          title: Text(context.l10n.permissionBattery),
          subtitle: Text(_batteryStatusText()),
          onTap: _requestBatteryOptimization,
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
        id: 'interval',
        title: l10n.requestInterval,
        subtitle: l10n.requestIntervalSubtitle(app.settings.requestInterval),
        keywords: l10n.requestIntervalKeywords.split(' '),
        category: 'connection',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(context.l10n.requestInterval),
          subtitle: Text(
            context.l10n.requestIntervalSubtitle(app.settings.requestInterval),
          ),
          onTap: () => _pickInterval(context),
        ),
      ),
      _Entry(
        id: 'max_uploads',
        title: l10n.maxUploads,
        subtitle: '${app.settings.maxUploads}',
        keywords: l10n.uploadKeywords.split(' '),
        category: 'connection',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.upload_outlined),
          title: Text(context.l10n.maxUploads),
          subtitle: Text('${app.settings.maxUploads}'),
          onTap: () => _pickConcurrency(context, true),
        ),
      ),
      _Entry(
        id: 'max_downloads',
        title: l10n.maxDownloads,
        subtitle: '${app.settings.maxDownloads}',
        keywords: l10n.downloadKeywords.split(' '),
        category: 'connection',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(context.l10n.maxDownloads),
          subtitle: Text('${app.settings.maxDownloads}'),
          onTap: () => _pickConcurrency(context, false),
        ),
      ),
      _Entry(
        id: 'api_host',
        title: l10n.apiHost,
        subtitle:
            app.settings.apiHost == 'up' ? 'up.woozooo.com' : 'pc.woozooo.com',
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
        id: 'upload_domain',
        title: l10n.uploadDomain,
        subtitle: app.settings.uploadDomain.isEmpty
            ? l10n.defaultUploadDomain
            : app.settings.uploadDomain,
        keywords: l10n.uploadDomainKeywords.split(' '),
        category: 'advanced',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text(context.l10n.uploadDomain),
          subtitle: Text(
            app.settings.uploadDomain.isEmpty
                ? context.l10n.defaultUploadDomain
                : app.settings.uploadDomain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _editUploadDomain(context),
        ),
      ),
      _Entry(
        id: 'share_domain',
        title: l10n.shareDomain,
        subtitle: app.settings.shareDomain.isEmpty
            ? l10n.defaultShareDomain
            : app.settings.shareDomain,
        keywords: l10n.shareDomainKeywords.split(' '),
        category: 'advanced',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.link_outlined),
          title: Text(context.l10n.shareDomain),
          subtitle: Text(
            app.settings.shareDomain.isEmpty
                ? context.l10n.defaultShareDomain
                : app.settings.shareDomain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _editShareDomain(context),
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
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text(context.l10n.backupAndRestore),
          subtitle: Text(context.l10n.backupAndRestoreSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BackupPage()),
          ),
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
        build: (context, app) => ListTile(
          leading: const Icon(Icons.history),
          title: Text(context.l10n.recentLimit),
          subtitle: Text(
            app.settings.recentLimit <= 0
                ? context.l10n.recentLimitOff
                : context.l10n.recentLimitValue(app.settings.recentLimit),
          ),
          onTap: () => _pickRecentLimit(context),
        ),
      ),
      _Entry(
        id: 'clear_recents',
        title: l10n.clearRecents,
        subtitle: l10n.clearRecentsSubtitle,
        keywords: l10n.clearRecentsKeywords.split(' '),
        category: 'data',
        build: (context, app) => ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(context.l10n.clearRecents),
          subtitle: Text(context.l10n.clearRecentsSubtitle),
          onTap: () async {
            await app.db.clearRecents(app.activeUid ?? '');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.cleared)),
              );
            }
          },
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
    ];
  }

  String _seedName(BuildContext context, int seed) => switch (seed) {
        0xFF2E6BE6 => context.l10n.classicBlue,
        0xFF00897B => context.l10n.teal,
        0xFF7B4DFF => context.l10n.violet,
        0xFFE5533D => context.l10n.vermilion,
        0xFF3F7D20 => context.l10n.olive,
        _ => context.l10n.custom,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final entries = _entries(app);
    final query = _search.text.trim().toLowerCase();

    final matching = entries
        .where((e) =>
            e.title.toLowerCase().contains(query) ||
            e.subtitle.toLowerCase().contains(query) ||
            _categoryName(e.category).toLowerCase().contains(query) ||
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
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  backgroundColor: Color.lerp(
                    scheme.surface,
                    scheme.surfaceContainer,
                    ScrollTint.of(context),
                  ),
                  scrolledUnderElevation: 0,
                  title: _searching
                      ? TextField(
                          controller: _search,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: l10n.searchSettings,
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        )
                      : Text(l10n.settings),
                  actions: [
                    IconButton(
                      tooltip: _searching ? l10n.closeSearch : l10n.searchSettings,
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
    final l10n = context.l10n;
    final groups = <String, List<_Entry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.category, () => []).add(e);
    }
    final widgets = <Widget>[];
    for (final name in groups.keys) {
      if (name == 'advanced') {
        widgets
          ..add(_sectionTitle(context, l10n.categoryAdvanced))
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
        ..add(_sectionTitle(context, _categoryName(name)))
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

  String _cameraStatusText() => switch (_permissions?.camera) {
        PermissionState.granted => context.l10n.permissionGranted,
        PermissionState.denied => context.l10n.permissionDenied,
        PermissionState.blocked => context.l10n.permissionBlocked,
        _ => context.l10n.permissionChecking,
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

  Future<void> _requestCameraPermission() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final state = await AppPermissions.instance.requestCamera();
    if (!mounted) return;
    await _refreshPermissions();
    if (!mounted) return;
    if (state == PermissionState.blocked) {
      final open = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.lock_outline),
          title: Text(l10n.permissionBlockedTitle),
          content: Text(l10n.permissionBlockedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.permissionOpenSystemSettings),
            ),
          ],
        ),
      );
      if (open == true) {
        final ok = await AppPermissions.instance.openAppSettings();
        if (!ok && mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.permissionOpenFailed)),
          );
        }
      }
      return;
    }
    if (state == PermissionState.granted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.permissionCameraGranted)),
      );
    }
  }

  Future<void> _openInstallSettings() async {
    final l10n = context.l10n;
    final ok = await AppPermissions.instance.openInstallSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.permissionOpenFailed)),
      );
    }
  }

  /// 打开系统的「默认打开链接」设置页（Android 12+）。
  Future<void> _openDefaultLinkSettings() async {
    final l10n = context.l10n;
    final ok = await AppPermissions.instance.openDefaultLinkSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.permissionOpenFailed)),
      );
    }
  }

  /// 导出运行日志：合并本机日志交到系统分享面板。
  Future<void> _exportLogs(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await AppLog.instance.exportBundle();
      if (!mounted) return;
      if (file == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.exportLogsEmpty)),
        );
        return;
      }
      final ok = await SystemShare.shareFile(
        file.path,
        subject: '${l10n.appName} ${l10n.exportLogs}',
        mime: 'text/plain',
      );
      if (!ok && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.exportLogsFailed)),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.exportLogsFailed)),
        );
      }
    }
  }

  Future<void> _requestBatteryOptimization() async {
    final l10n = context.l10n;
    final ok = await AppPermissions.instance.requestBattery();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.permissionOpenFailed)),
      );
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
        children: [
          for (final entry in matching) entry.build(context, app),
        ],
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
    final l10n = context.l10n;
    final custom = app.settings.downloadDir;
    // 默认目录直接显示真实路径
    final current = custom != null && custom.isNotEmpty
        ? custom
        : l10n.defaultDownloadDir(await app.defaultDownloadDirPath());
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.downloadDir),
        content: Text(current),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.pickDirFailed('$e'))),
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
      options: [
        ('page', l10n.openInNewPage),
        ('drive', l10n.openInDriveTab),
      ],
      current: app.settings.homeFolderOpenMode,
      onSelect: (value) => app.setHomeFolderOpenMode(value),
    );
  }

  static Future<void> _pickThemeMode(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _pickRadio(
      context,
      title: l10n.themeMode,
      options: [
        ('system', l10n.followSystem),
        ('light', l10n.light),
        ('dark', l10n.dark),
      ],
      current: app.settings.themeMode,
      onSelect: (value) => app.setThemeMode(value),
    );
  }

  /// 最近使用条数：0 表示不记录。
  static Future<void> _pickRecentLimit(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _pickRadio<int>(
      context,
      title: l10n.recentLimit,
      options: [
        (0, l10n.recentLimitOff),
        for (final count in const [10, 50, 100, 200])
          (count, l10n.recentLimitValue(count)),
      ],
      current: app.settings.recentLimit,
      onSelect: app.setRecentLimit,
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
    final l10n = context.l10n;
    final presets = <int, String>{
      0xFF2E6BE6: l10n.classicBlue,
      0xFF00897B: l10n.teal,
      0xFF7B4DFF: l10n.violet,
      0xFFE5533D: l10n.vermilion,
      0xFF3F7D20: l10n.olive,
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.themeColor),
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
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.requestInterval),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              l10n.requestIntervalHint,
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.outline,
                  ),
            ),
          ),
          // 不提供「不间隔」：过小间隔容易触发服务端限流
          for (final ms in const [25, 50, 75, 100, 150, 200, 300, 500, 1000])
            ListTile(
              title: Text('$ms ms'),
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
    final l10n = context.l10n;
    final max = upload ? 3 : 5;
    final current =
        upload ? app.settings.maxUploads : app.settings.maxDownloads;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(upload ? l10n.maxUploads : l10n.maxDownloads),
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

  static Future<void> _editUploadDomain(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _editText(
      context,
      title: l10n.uploadDomain,
      hint: l10n.uploadDomainHint,
      current: app.settings.uploadDomain,
      onSave: (value) => app.setUploadDomain(value),
    );
  }

  static Future<void> _editShareDomain(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _editText(
      context,
      title: l10n.shareDomain,
      hint: l10n.shareDomainHint,
      current: app.settings.shareDomain,
      onSave: (value) => app.setShareDomain(value),
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
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  backgroundColor: Color.lerp(
                    scheme.surface,
                    scheme.surfaceContainer,
                    ScrollTint.of(context),
                  ),
                  scrolledUnderElevation: 0,
                  title: Text(l10n.advanced),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
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
                            onTap: () =>
                                _SettingsPageState._pickApiHost(context),
                          ),
                          ListTile(
                            leading: const Icon(Icons.cloud_upload_outlined),
                            title: Text(l10n.uploadDomain),
                            subtitle: Text(
                              app.settings.uploadDomain.isEmpty
                                  ? l10n.defaultUploadDomain
                                  : app.settings.uploadDomain,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _SettingsPageState
                                ._editUploadDomain(context),
                          ),
                          ListTile(
                            leading: const Icon(Icons.link_outlined),
                            title: Text(l10n.shareDomain),
                            subtitle: Text(
                              app.settings.shareDomain.isEmpty
                                  ? l10n.defaultShareDomain
                                  : app.settings.shareDomain,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () =>
                                _SettingsPageState._editShareDomain(context),
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
                            onTap: () =>
                                _SettingsPageState._editUserAgent(context),
                          ),
                        ],
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
