import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
import 'clipboard_link_prompt_tile.dart';
import 'common.dart';
import 'cookie_sheet.dart';
import 'licenses_page.dart';
import 'm3e.dart';

/// 「清除数据」弹窗里可勾选的清除项。
enum _ClearDataOption { quickAccess, recents, otherAccounts, logs, registry }

/// 「无障碍相关问题」反馈邮箱。
const String _kA11yFeedbackEmail = 'lancloud_feedback@outlook.com';

/// 设置大类：设置内容拆成 5 页。「我的」页里的「设置」类别列表、小屏
/// 独立打开的二级页、宽窗口下「我的」右侧详情窗格都用同一批页面。
enum SettingsCategory {
  appearanceLayout,
  behaviorPermissions,
  notificationsReminders,
  transferConnection,
  privacyData;

  /// 类别名（「我的」里类别行的标题 / 二级页标题）。
  String label(AppLocalizations l10n) => switch (this) {
    SettingsCategory.appearanceLayout => l10n.categoryAppearanceLayout,
    SettingsCategory.behaviorPermissions => l10n.categoryBehaviorPermissions,
    SettingsCategory.notificationsReminders =>
      l10n.categoryNotificationsReminders,
    SettingsCategory.transferConnection => l10n.categoryTransferConnection,
    SettingsCategory.privacyData => l10n.categoryPrivacyData,
  };

  /// 「我的」里类别行的图标。
  IconData get icon => switch (this) {
    SettingsCategory.appearanceLayout => Icons.palette_outlined,
    SettingsCategory.behaviorPermissions => Icons.view_cozy,
    SettingsCategory.notificationsReminders => Icons.notifications_outlined,
    SettingsCategory.transferConnection => Icons.swap_vertical_circle,
    SettingsCategory.privacyData => Icons.text_snippet,
  };
}

/// 大类页里的分组小标题（外观 / 布局 / 行为 / …）：
/// 每个小节渲染成「小标题 + 列表组」。
enum SettingsSection {
  appearance(SettingsCategory.appearanceLayout),
  layout(SettingsCategory.appearanceLayout),
  behavior(SettingsCategory.behaviorPermissions),
  accessibility(SettingsCategory.behaviorPermissions),
  permissions(SettingsCategory.behaviorPermissions),
  notification(SettingsCategory.notificationsReminders),
  reminder(SettingsCategory.notificationsReminders),
  download(SettingsCategory.transferConnection),
  upload(SettingsCategory.transferConnection),
  connection(SettingsCategory.transferConnection),
  backup(SettingsCategory.privacyData),
  privacy(SettingsCategory.privacyData),
  data(SettingsCategory.privacyData);

  const SettingsSection(this.category);

  /// 本小节属于哪个大类页。
  final SettingsCategory category;

  /// 分组小标题文案。
  String label(AppLocalizations l10n) => switch (this) {
    SettingsSection.appearance => l10n.categoryAppearance,
    SettingsSection.layout => l10n.sectionLayout,
    SettingsSection.behavior => l10n.categoryBehavior,
    SettingsSection.accessibility => l10n.categoryAccessibility,
    SettingsSection.permissions => l10n.categoryPermissions,
    SettingsSection.notification => l10n.notifications,
    SettingsSection.reminder => l10n.sectionReminder,
    SettingsSection.download => l10n.sectionDownload,
    SettingsSection.upload => l10n.sectionUpload,
    SettingsSection.connection => l10n.categoryConnection,
    SettingsSection.backup => l10n.backupAndRestore,
    SettingsSection.privacy => l10n.categoryPrivacy,
    SettingsSection.data => l10n.categoryData,
  };
}

/// 单个设置大类页：独立打开（小屏 push / 大屏单栏页）或嵌在「我的」右侧
/// 详情窗格里。两种形态共用同一份条目与搜索逻辑，只是外壳不同。
class SettingsCategoryPage extends StatefulWidget {
  const SettingsCategoryPage({
    super.key,
    required this.category,
    this.embedded = false,
    this.searching = false,
    this.query = '',
    this.onSwitchCategory,
    this.onOpenSubPage,
    this.scrollController,
  });

  /// 本页展示哪个大类。
  final SettingsCategory category;

  /// 嵌在「我的」右侧详情窗格里：不画顶栏，页内也只有正文
  /// （标题 / 搜索在「我的」页的顶栏上）。
  final bool embedded;

  /// 嵌入窗格时由外层顶栏持有的搜索状态：`true` 时正文换成搜索结果。
  final bool searching;

  /// 嵌入窗格时的搜索关键词。
  final String query;

  /// [embedded] 时：搜索命中其他类别、点击切换后通知外层更新选中项。
  final ValueChanged<SettingsCategory>? onSwitchCategory;

  /// [embedded] 时：点开设置二级页（高级覆盖项 / 备份与恢复）时
  /// 通知外层把窗格内容换成二级页；不传时按独立页 push。
  final ValueChanged<ProfileSubPage>? onOpenSubPage;

  /// 滚动控制器；不传时页面自建。嵌入窗格时由外层持有，
  /// 切换类别再切回来滚动位置不丢。
  final ScrollController? scrollController;

  @override
  State<SettingsCategoryPage> createState() => _SettingsCategoryPageState();
}

class _Entry {
  const _Entry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.section,
    required this.build,
    this.visible,
    this.inAdvancedPage = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> keywords;

  /// 所属分组小节：决定它出现在哪个大类页的哪个小标题下。
  final SettingsSection section;

  final Widget Function(BuildContext context, AppController app) build;

  /// 是否显示（默认显示）。跟随当前主题等运行时状态的条件项用它。
  final bool Function(BuildContext context, AppController app)? visible;

  /// 只出现在「高级覆盖项」二级页：本页列表不渲染，仅参与搜索
  /// （搜索结果里点击直达高级覆盖项页）。
  final bool inAdvancedPage;
}

class _SettingsCategoryPageState extends State<SettingsCategoryPage>
    with WidgetsBindingObserver {
  bool _searching = false;
  bool? _notifGranted;

  /// 动态取色支持情况：进入设置页探测一次（带缓存），不放在会随
  /// 搜索 / 滚动重建的 tile 里反复查询。
  bool? _dynamicColorSupported;
  PermissionSnapshot? _permissions;

  /// 默认下载目录的真实路径（副标题里显示，进入设置时读一次）。
  String? _defaultDownloadDir;

  /// 应用专属目录的根与外部存储根：
  /// 副标题用它给下载目录分类（仅 Android）。
  List<String> _privateDirRoots = const [];
  String? _publicDirRoot;
  final TextEditingController _search = TextEditingController();

  /// 页面自建的滚动控制器；外层传入 [SettingsCategoryPage.scrollController]
  /// 时不用它，销毁时也不释放外层的。
  ScrollController? _ownScroll;

  /// 设置页列表；传给 TopBarOverlayScaffold / FastScrollbar 后
  /// 点顶栏空白即可回到顶部。
  ScrollController get _list =>
      widget.scrollController ?? (_ownScroll ??= ScrollController());

  /// 搜索态与关键词：独立页用自己的状态，嵌入窗格时用外层顶栏传进来的。
  bool get _searchActive => widget.embedded ? widget.searching : _searching;
  String get _searchText => widget.embedded ? widget.query : _search.text;

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
        final roots = <String>{};
        try {
          final external = await getExternalStorageDirectory();
          if (external != null && external.path.isNotEmpty) {
            roots.add(external.path);
          }
        } catch (_) {
          // 拿不到外部专属目录就少一个私有根，不影响判断
        }
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

  /// 下载目录副标题：未自定义时显示「默认（路径）」；显式设置的 Android
  /// 目录按分类加前缀（私有 / 公共 / 非公共）。
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
    return l10n.defaultDownloadDir(path);
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
              Text(
                l10n.navBarItemsHint,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
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
    _ownScroll?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsCategoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 独立页切到别的类别：收掉上一页的搜索状态
    //（嵌入窗格时搜索状态在外层「我的」页，不在这里处理）
    if (!widget.embedded &&
        oldWidget.category != widget.category &&
        _searching) {
      _searching = false;
      _search.clear();
    }
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
    String motionModeName() => switch (app.settings.motionMode) {
      'on' => l10n.motionModeEnabled,
      'off' => l10n.motionModeDisabled,
      _ => l10n.motionModeAuto,
    };
    return [
      _Entry(
        id: 'language',
        title: l10n.language,
        subtitle: languageName(),
        keywords: const ['language', 'locale', 'zh', 'en', '语言', '中文', '英语'],
        section: SettingsSection.appearance,
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
        section: SettingsSection.appearance,
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
        section: SettingsSection.appearance,
        // 纯黑只对深色界面有意义：深色模式、或「跟随系统」且系统是深色时
        // 才出现（等价于「当前实际是深色界面」）。
        visible: (context, app) =>
            Theme.of(context).brightness == Brightness.dark,
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
        // 开了动态取色就显示「动态取色」，否则显示当前颜色名
        //（动态取色也是弹窗里的一个选项，见 _pickThemeSeed）
        subtitle: app.settings.dynamicColor
            ? l10n.dynamicColor
            : _seedName(context, app.settings.themeSeed),
        keywords: [
          ...l10n.themeColorKeywords.split(' '),
          ...l10n.dynamicColorKeywords.split(' '),
        ],
        section: SettingsSection.appearance,
        build: (context, app) {
          final dynamicColor = app.settings.dynamicColor;
          return ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(context.l10n.themeColor),
            subtitle: Text(
              dynamicColor
                  ? context.l10n.dynamicColor
                  : _seedName(context, app.settings.themeSeed),
            ),
            // 动态取色时没有固定颜色可展示，尾部不再画色块
            trailing: dynamicColor
                ? null
                : CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(app.settings.themeSeed),
                  ),
            onTap: () => _pickThemeSeed(
              context,
              // 探测完成前按「支持」处理（与旧开关一致），避免闪一下置灰
              dynamicSupported: _dynamicColorSupported ?? true,
            ),
          );
        },
      ),
      _Entry(
        id: 'hide_top_bar',
        title: l10n.hideTopBar,
        subtitle: '',
        keywords: l10n.hideTopBarKeywords.split(' '),
        section: SettingsSection.layout,
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.vertical_align_top),
          title: Text(context.l10n.hideTopBar),
          value: app.settings.hideTopBar,
          onChanged: (value) => app.setHideTopBar(value),
        ),
      ),
      _Entry(
        id: 'hide_bottom_bar',
        title: l10n.hideBottomBar,
        subtitle: '',
        keywords: l10n.hideBottomBarKeywords.split(' '),
        section: SettingsSection.layout,
        build: (context, app) => SwitchListTile(
          secondary: const Icon(Icons.vertical_align_bottom),
          title: Text(context.l10n.hideBottomBar),
          value: app.settings.hideBottomBar,
          onChanged: (value) => app.setHideBottomBar(value),
        ),
      ),
      _Entry(
        id: 'floating_nav',
        title: l10n.floatingNav,
        subtitle: '',
        keywords: l10n.floatingNavKeywords.split(' '),
        section: SettingsSection.appearance,
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
        section: SettingsSection.layout,
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
        section: SettingsSection.layout,
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
        section: SettingsSection.appearance,
        build: (context, app) => SwitchListTile(
          // 与「无障碍-全局动画」区分：这里用 Auto Awesome Motion
          secondary: const Icon(Icons.auto_awesome_motion),
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
        section: SettingsSection.download,
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
        section: SettingsSection.behavior,
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
        section: SettingsSection.behavior,
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
        section: SettingsSection.behavior,
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
        section: SettingsSection.behavior,
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
        section: SettingsSection.notification,
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
        section: SettingsSection.notification,
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
        section: SettingsSection.reminder,
        build: (context, app) => const ClipboardLinkPromptTile(),
      ),
      // 三项系统权限（通知 / 安装应用 / 忽略电池优化）收进一个弹窗，
      // 设置页只留一个「管理权限」入口
      _Entry(
        id: 'manage_permissions',
        title: l10n.managePermissions,
        subtitle: '',
        keywords: [
          ...l10n.managePermissionsKeywords.split(' '),
          ...l10n.permissionInstallKeywords.split(' '),
          ...l10n.permissionBatteryKeywords.split(' '),
          ...l10n.notifPermissionKeywords.split(' '),
        ],
        section: SettingsSection.permissions,
        build: (context, app) => ListTile(
          leading: const Icon(Icons.shield),
          title: Text(context.l10n.managePermissions),
          onTap: () => _showManagePermissions(context),
        ),
      ),
      _Entry(
        id: 'default_links',
        title: l10n.manageDefaultLinks,
        subtitle: l10n.manageDefaultLinksSubtitle,
        keywords: l10n.manageDefaultLinksKeywords.split(' '),
        section: SettingsSection.permissions,
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
        section: SettingsSection.permissions,
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
        section: SettingsSection.connection,
        build: (context, app) => _SliderTile<int>(
          icon: Icons.timer_outlined,
          title: context.l10n.requestInterval,
          // 提醒间隔过小会被服务器限流（放在滑杆上方当副标题）
          subtitle: context.l10n.requestIntervalHint,
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
        section: SettingsSection.upload,
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
        section: SettingsSection.download,
        build: (context, app) => _SliderTile<int>(
          icon: Icons.download_outlined,
          title: context.l10n.maxDownloads,
          values: const [1, 2, 3, 4, 5],
          current: app.settings.maxDownloads,
          labelOf: (value) => '$value',
          onChanged: app.setMaxDownloads,
        ),
      ),
      // 高级覆盖项入口：排在「连接」组最后（不再单占一组）
      _Entry(
        id: 'advanced',
        title: l10n.advanced,
        subtitle: '',
        keywords: const [
          'advanced',
          'api',
          '接口',
          '上传路径',
          'ua',
          'user agent',
          '覆盖',
        ],
        section: SettingsSection.connection,
        build: (context, app) => ListTile(
          leading: const Icon(Icons.tune),
          title: Text(context.l10n.advanced),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openSubPage(context, ProfileSubPage.advanced),
        ),
      ),
      _Entry(
        id: 'api_host',
        title: l10n.apiHost,
        subtitle: app.settings.apiHost == 'up'
            ? 'up.woozooo.com'
            : 'pc.woozooo.com',
        keywords: l10n.apiHostKeywords.split(' '),
        section: SettingsSection.connection,
        inAdvancedPage: true,
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
        section: SettingsSection.connection,
        inAdvancedPage: true,
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
        section: SettingsSection.connection,
        inAdvancedPage: true,
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
        section: SettingsSection.backup,
        build: (context, app) => ListTile(
          leading: const Icon(Icons.sync),
          title: Text(context.l10n.backupAndRestore),
          subtitle: Text(context.l10n.backupAndRestoreSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openSubPage(context, ProfileSubPage.backup),
        ),
      ),
      _Entry(
        id: 'recent_limit',
        title: l10n.recentLimit,
        subtitle: app.settings.recentLimit <= 0
            ? l10n.recentLimitOff
            : l10n.recentLimitValue(app.settings.recentLimit),
        keywords: l10n.recentLimitKeywords.split(' '),
        section: SettingsSection.data,
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
        id: 'clear_cache',
        title: l10n.clearCache,
        subtitle: l10n.clearCacheSubtitle,
        keywords: l10n.clearCacheKeywords.split(' '),
        section: SettingsSection.data,
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
        section: SettingsSection.privacy,
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
        section: SettingsSection.privacy,
        build: (context, app) => ListTile(
          leading: const Icon(Icons.article_outlined),
          title: Text(context.l10n.exportLogs),
          subtitle: Text(context.l10n.exportLogsSubtitle),
          onTap: () => _exportLogs(context),
        ),
      ),
      _Entry(
        id: 'clear_data',
        title: l10n.clearData,
        subtitle: '',
        keywords: l10n.clearDataKeywords.split(' '),
        section: SettingsSection.privacy,
        build: (context, app) => ListTile(
          leading: const Icon(Icons.ink_eraser),
          title: Text(context.l10n.clearData),
          onTap: () => _clearData(context),
        ),
      ),
      _Entry(
        id: 'motion_mode',
        title: l10n.globalAnimations,
        subtitle: motionModeName(),
        keywords: l10n.motionModeKeywords.split(' '),
        section: SettingsSection.accessibility,
        build: (context, app) => ListTile(
          leading: const Icon(Icons.animation),
          title: Text(context.l10n.globalAnimations),
          subtitle: Text(motionModeName()),
          onTap: () => _pickMotionMode(context),
        ),
      ),
      _Entry(
        id: 'a11y_feedback',
        title: l10n.a11yFeedback,
        subtitle: '',
        keywords: l10n.a11yFeedbackKeywords.split(' '),
        section: SettingsSection.accessibility,
        build: (context, app) => ListTile(
          leading: const Icon(Icons.mail_outlined),
          title: Text(context.l10n.a11yFeedback),
          onTap: () => _showA11yFeedbackDialog(context),
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

  /// 打开设置二级页：嵌在「我的」右窗格时交给外层换窗格内容，
  /// 独立页保持 push。
  void _openSubPage(BuildContext context, ProfileSubPage sub) {
    final open = widget.onOpenSubPage;
    if (widget.embedded && open != null) {
      open(sub);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (sub) {
          ProfileSubPage.advanced => const _AdvancedPage(),
          ProfileSubPage.backup => const BackupPage(),
          ProfileSubPage.licenses => const LicensesPage(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    final entries = _entries(app)
        .where((e) => e.visible?.call(context, app) ?? true)
        .toList();
    final query = _searchText.trim().toLowerCase();

    final matching = entries
        .where(
          (e) =>
              e.title.toLowerCase().contains(query) ||
              e.subtitle.toLowerCase().contains(query) ||
              e.section.label(l10n).toLowerCase().contains(query) ||
              e.section.category.label(l10n).toLowerCase().contains(query) ||
              e.keywords.any((k) => k.toLowerCase().contains(query)),
        )
        .toList();

    // 本页内容：正常态 = 各分组小节；搜索态 = 本页命中 + 「其他设置项」
    final children = _searchActive
        ? _buildSearchResults(context, app, matching)
        : _buildSections(context, app, entries);

    if (widget.embedded) return _buildEmbedded(children);

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
            title: Text(widget.category.label(l10n)),
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
          M3eReadingSliverPadding(
            padding: kM3eSectionPagePadding,
            // 整块布局：分组高度差异大，懒布局会让 maxScrollExtent 一直修正、
            // 滚动条滑块长度抖动（见 SliverColumn 注释）
            // 整块布局：分组高度差异大，懒布局会让 maxScrollExtent 一直修正、
            // 滚动条滑块长度抖动（见 SliverColumn 注释）
            sliver: SliverColumn(children: children),
          ),
        ],
      ),
    );
  }

  /// 嵌在「我的」右侧详情窗格里的形态：只有正文（标题 / 搜索在外层顶栏），
  /// 卡片外形（圆角、底色）由「我的」页统一提供。
  Widget _buildEmbedded(List<Widget> children) {
    // 顶栏是「我的」页的浮层：正文顶上留出等高占位（与其它页一致），
    // 顶栏收起时随内容滚走；滑块也不要从顶栏下面露头。
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return FastScrollbar(
      controller: _list,
      padding: EdgeInsets.only(
        top: headerHeight,
        bottom: shellBottomBarInset(context),
      ),
      child: CustomScrollView(
        controller: _list,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
          SliverPadding(
            padding: kM3eSectionPagePadding,
            // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
            sliver: SliverColumn(children: children),
          ),
        ],
      ),
    );
  }

  /// 本页的分组小节：每个小节 = 小标题 + 一组设置项列表。
  List<Widget> _buildSections(
    BuildContext context,
    AppController app,
    List<_Entry> entries,
  ) {
    final widgets = <Widget>[];
    for (final section in SettingsSection.values) {
      if (section.category != widget.category) continue;
      // 高级覆盖项下的条目（接口域名 / 上传路径 / UA）只在二级页与搜索里出现
      final list = entries
          .where((e) => e.section == section && !e.inAdvancedPage)
          .toList();
      if (list.isEmpty) continue;
      widgets
        ..add(M3eSectionHeader(section.label(context.l10n)))
        ..add(
          SegmentedList(
            children: [for (final entry in list) entry.build(context, app)],
          ),
        );
    }
    return widgets;
  }

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

  /// 「清除数据」：多选要清除的数据（此账号的快速访问 / 最近使用、其它数据），
  /// 确认后一次性清掉。样式与其它选择弹窗一致（分组小标题 + 列表组复选行）。
  Future<void> _clearData(BuildContext context) async {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    final selected = <_ClearDataOption>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Widget group(String name, List<_ClearDataOption> options) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 弹窗里列表组外边距为 0：标题也无缩进，与外沿对齐
              M3eSectionHeader(name, horizontalInset: 0),
              DialogListGroup(
                children: [
                  for (final option in options)
                    M3ePickTile(
                      label: _clearDataName(l10n, option),
                      subtitle: _clearDataSubtitle(l10n, option),
                      selected: selected.contains(option),
                      onTap: () => setDialogState(() {
                        if (!selected.remove(option)) selected.add(option);
                      }),
                    ),
                ],
              ),
            ],
          );

          return AlertDialog(
            title: Text(l10n.clearData),
            // M3 对话框内容边距 24dp；列表组自带 0 外边距，组沿落在 24dp 上
            contentPadding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 「此账号」两项只有登录状态下才有意义
                  if (app.activeUid != null)
                    group(l10n.clearDataGroupAccount, const [
                      _ClearDataOption.quickAccess,
                      _ClearDataOption.recents,
                    ]),
                  group(l10n.clearDataGroupOthers, [
                    _ClearDataOption.otherAccounts,
                    _ClearDataOption.logs,
                    // 通知注册表键只有 Windows 端才会创建
                    if (PlatformSupport.isWindows) _ClearDataOption.registry,
                  ]),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                // 一项都没勾选时置灰：先选内容再清除
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.clear),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    if (selected.isEmpty) {
      // 什么都没选就点「清除」：明确提示未选择，而不是假装清空成功
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.clearDataNothingSelected)));
      return;
    }
    final uid = app.activeUid ?? '';
    try {
      if (selected.contains(_ClearDataOption.quickAccess)) {
        await app.db.clearPins(uid);
      }
      if (selected.contains(_ClearDataOption.recents)) {
        await app.db.clearRecents(uid);
      }
      if (selected.contains(_ClearDataOption.otherAccounts)) {
        await app.db.clearOtherUsageData(uid);
      }
    } catch (_) {
      // 本地库出错时静默跳过：清除是尽力而为，不打断用户
    }
    if (selected.contains(_ClearDataOption.logs)) {
      await AppLog.instance.clear();
    }
    if (selected.contains(_ClearDataOption.registry)) {
      NotificationService.removeWindowsRegistryEntry();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.cleared)));
  }

  String _clearDataName(AppLocalizations l10n, _ClearDataOption option) =>
      switch (option) {
        _ClearDataOption.quickAccess => l10n.quickAccess,
        _ClearDataOption.recents => l10n.recent,
        _ClearDataOption.otherAccounts => l10n.clearDataOtherAccounts,
        _ClearDataOption.logs => l10n.clearDataLogs,
        _ClearDataOption.registry => l10n.clearDataRegistry,
      };

  String? _clearDataSubtitle(AppLocalizations l10n, _ClearDataOption option) =>
      switch (option) {
        _ClearDataOption.otherAccounts => l10n.clearDataOtherAccountsSubtitle,
        _ClearDataOption.registry => l10n.clearDataRegistrySubtitle,
        _ => null,
      };

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
            margin: SheetListGroup.endMargin,
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
    );
  }

  /// 搜索结果：优先本页命中的条目（按分组小节分块），其余类别归入
  /// 「其他设置项」，点击切换到对应设置页。
  List<Widget> _buildSearchResults(
    BuildContext context,
    AppController app,
    List<_Entry> matching,
  ) {
    final l10n = context.l10n;
    if (_searchText.trim().isEmpty) {
      return [
        const SizedBox(height: 48),
        Center(child: Text(l10n.searchPlaceholder)),
      ];
    }
    final mine = matching
        .where(
          (e) => !e.inAdvancedPage && e.section.category == widget.category,
        )
        .toList();
    final others = matching
        .where((e) => e.inAdvancedPage || e.section.category != widget.category)
        .toList();
    if (mine.isEmpty && others.isEmpty) {
      return [const SizedBox(height: 48), Center(child: Text(l10n.noMatch))];
    }
    final widgets = <Widget>[];
    for (final section in SettingsSection.values) {
      if (section.category != widget.category) continue;
      final list = mine.where((e) => e.section == section).toList();
      if (list.isEmpty) continue;
      widgets
        ..add(M3eSectionHeader(section.label(l10n)))
        ..add(
          SegmentedList(
            children: [for (final entry in list) entry.build(context, app)],
          ),
        );
    }
    if (others.isNotEmpty) {
      widgets
        ..add(M3eSectionHeader(l10n.searchOtherSettings))
        ..add(
          SegmentedList(
            children: [
              for (final entry in others) _otherResultTile(context, entry),
            ],
          ),
        );
    }
    return widgets;
  }

  /// 「其他设置项」里的行：纯导航行（只显示所在大类），点击切到对应设置页。
  Widget _otherResultTile(BuildContext context, _Entry entry) {
    final l10n = context.l10n;
    final target = entry.inAdvancedPage
        ? l10n.categoryAdvanced
        : entry.section.category.label(l10n);
    return ListTile(
      title: Text(entry.title),
      subtitle: Text(target, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openSearchTarget(entry),
    );
  }

  /// 搜索结果里点「其他设置项」：
  /// - 独立页：pushReplacement 换成目标页（小屏上来回点不会堆出一串设置页）；
  /// - 详情窗格：通知外层切换选中的类别；
  /// - 「高级覆盖项」下的条目：打开高级覆盖项页（窗格内直接盖一层）。
  void _openSearchTarget(_Entry entry) {
    if (entry.inAdvancedPage) {
      // 窗格内直接换成高级覆盖项页；独立页 pushReplacement 换成它
      if (widget.embedded && widget.onOpenSubPage != null) {
        widget.onOpenSubPage!(ProfileSubPage.advanced);
        return;
      }
      final route = MaterialPageRoute<void>(
        builder: (_) => const _AdvancedPage(),
      );
      if (widget.embedded) {
        Navigator.of(context).push(route);
      } else {
        Navigator.of(context).pushReplacement(route);
      }
      return;
    }
    final target = entry.section.category;
    if (widget.embedded) {
      widget.onSwitchCategory?.call(target);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SettingsCategoryPage(category: target),
      ),
    );
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
                final dir = await FilePicker.getDirectoryPath();
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
    String? Function(T value)? subtitleOf,
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
              // 比弹窗底（surfaceContainerHigh）再高一档容器色
              DialogListGroup(
                children: [
                  for (final entry in options)
                    M3ePickTile(
                      label: entry.$2,
                      subtitle: subtitleOf?.call(entry.$1),
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

  /// 「全局动画」：auto（跟随无障碍功能）/ on（始终启用）/ off（始终禁用）。
  static Future<void> _pickMotionMode(BuildContext context) {
    final app = context.read<AppController>();
    final l10n = context.l10n;
    return _pickRadio(
      context,
      title: l10n.globalAnimations,
      options: [
        ('auto', l10n.motionModeAuto),
        ('on', l10n.motionModeEnabled),
        ('off', l10n.motionModeDisabled),
      ],
      // 默认档的说明（另外两档看名字即可）
      subtitleOf: (value) =>
          value == 'auto' ? l10n.motionModeAutoSubtitle : null,
      current: app.settings.motionMode,
      onSelect: (value) => app.setMotionMode(value),
    );
  }

  /// 「无障碍相关问题」：先在弹窗里说明用途，确认后复制反馈邮箱并唤起邮件。
  static Future<void> _showA11yFeedbackDialog(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.a11yFeedbackDialogTitle),
        content: Text(l10n.a11yFeedbackDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.feedback),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // 先复制邮箱：即使设备上没有邮件应用，用户也拿到了地址
    await Clipboard.setData(const ClipboardData(text: _kA11yFeedbackEmail));
    if (!context.mounted) return;
    showAppToast(context, l10n.emailCopied);
    await launchUrl(
      Uri(scheme: 'mailto', path: _kA11yFeedbackEmail),
      mode: LaunchMode.externalApplication,
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

  /// 「主题色」单选弹窗：第一项是动态取色（系统不支持时置灰）、其余是预设
  /// 主题色；两者互斥——选了颜色即关闭动态取色，选动态取色则颜色不生效。
  static Future<void> _pickThemeSeed(
    BuildContext context, {
    required bool dynamicSupported,
  }) async {
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
    // 不支持时动态取色按未选中处理（也点不动）
    final dynamicSelected = dynamicSupported && app.settings.dynamicColor;
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
              // 与其它选择弹窗同一套列表组样式：选中 = 主容器色 + 对勾
              // 比弹窗底（surfaceContainerHigh）再高一档容器色
              DialogListGroup(
                children: [
                  M3ePickTile(
                    label: l10n.dynamicColor,
                    subtitle: dynamicSupported
                        ? l10n.dynamicColorSubtitle
                        : l10n.dynamicColorUnsupported,
                    selected: dynamicSelected,
                    singleSelect: true,
                    enabled: dynamicSupported,
                    leading: const Icon(Icons.wallpaper_outlined),
                    onTap: () async {
                      Navigator.of(dialogContext).pop();
                      await app.setDynamicColor(true);
                    },
                  ),
                  for (final entry in presets.entries)
                    M3ePickTile(
                      label: entry.value,
                      selected:
                          !dynamicSelected &&
                          app.settings.themeSeed == entry.key,
                      singleSelect: true,
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: Color(entry.key),
                      ),
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        // 与动态取色互斥：选具体颜色即关闭动态取色
                        await app.setDynamicColor(false);
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

/// 高级覆盖项正文：提示 + 接口域名 / 上传路径 / UA。
/// 独立页（push）与「我的」右窗格共用；外壳由宿主提供。
class AdvancedContent extends StatelessWidget {
  const AdvancedContent({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: InfoHintCard(text: l10n.advancedHint),
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
              onTap: () => _SettingsCategoryPageState._pickApiHost(context),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(l10n.uploadPath),
              subtitle: Text(
                app.settings.uploadPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _SettingsCategoryPageState._pickUploadPath(context),
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
              onTap: () => _SettingsCategoryPageState._editUserAgent(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// 高级覆盖项二级页（独立打开）。
class _AdvancedPage extends StatelessWidget {
  const _AdvancedPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TopBarOverlayScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(l10n.advanced),
      ),
      slivers: [
        M3eReadingSliverPadding(
          padding: kM3eSectionPagePadding.copyWith(top: 16),
          // 整块布局：避免懒布局估算导致滚动条滑块抖动（见 SliverColumn）
          sliver: const SliverToBoxAdapter(child: AdvancedContent()),
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
/// 标题与值单独成行，滑杆放在下方独立一行，避免 ListTile 为 trailing 预留的
/// 宽度同时挤压 subtitle；滑杆轨道横跨标题左缘到当前值右缘。
///
/// **本应用的设计决定（非 M3 规范）**：拖动时只更新本地显示，松手才写设置
/// （避免拖动过程中反复落盘）。
///
/// **无障碍**：M3ESlider 是纯自绘控件、自身不产出滑杆语义，TalkBack 既读不出
/// 当前值也无法调节；这里在外面合成滑杆语义节点（slider 角色 + 当前值 +
/// 上/下调动作），并屏蔽内部手势语义（否则读屏双击会按成控件中心点按）。
///
/// **旧版读屏兼容性**：6.1 一脉的旧 TalkBack（如 Android 12 时代的版本、部分
/// 系统内置读屏）调整后只播报「进度条」：旧逻辑的数值取自调整事件里的
/// itemCount/currentItemIndex（原生 SeekBar 会填这两个字段，Flutter 引擎不发，
/// 应用层无法补齐）；新版 TalkBack 走节点文本，值照常播报。不要加
/// SemanticsService.announce / liveRegion 之类补偿——会让新版重复播报。
class _SliderTile<T> extends StatefulWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;

  /// 可选的说明文字（滑杆上方的一行小字）。
  final String? subtitle;

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
    final scheme = theme.colorScheme;
    final value = widget.values[_index];
    return Padding(
      // 与 M3 单行 ListTile 的内容内边距一致：leading 16dp、trailing 24dp；
      // 上下 8dp 对应含副标题列表项的最小垂直留白。
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(widget.icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle!,
                              // 与其它设置项的 ListTile 副标题同一档
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 当前值与标题、副标题组成的文字列整体垂直居中；拖动时同步更新。
                    Text(
                      widget.labelOf(value),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // M3ESlider 的轨道两端各保留 thumbRadius（10dp）作为手柄的
                // 活动空间。把绘制区向左右各扩 10dp，轨道才会真正落在标题
                // 左缘和当前值右缘上，而不是缩进一截。
                LayoutBuilder(
                  builder: (context, constraints) {
                    const endpointInset = M3ESliderDefaults.thumbRadius;
                    final width = constraints.maxWidth + endpointInset * 2;
                    final height = M3ESliderDefaults.thumbRippleRadius * 2;
                    return SizedBox(
                      height: height,
                      child: OverflowBox(
                        minWidth: width,
                        maxWidth: width,
                        minHeight: height,
                        maxHeight: height,
                        child: Semantics(
                          container: true,
                          slider: true,
                          enabled: true,
                          label: widget.title,
                          value: widget.labelOf(value),
                          increasedValue: widget.labelOf(
                            widget.values[_clampIndex(_index + 1)],
                          ),
                          decreasedValue: widget.labelOf(
                            widget.values[_clampIndex(_index - 1)],
                          ),
                          onIncrease: () => _step(1),
                          onDecrease: () => _step(-1),
                          excludeSemantics: true,
                          child: M3ESlider(
                            key: ValueKey('settings-slider-${widget.title}'),
                            value: _index.toDouble(),
                            min: 0,
                            max: (widget.values.length - 1).toDouble(),
                            divisions: widget.values.length - 1,
                            onChanged: (v) =>
                                setState(() => _index = v.round()),
                            // 松手才落盘；用本地档位（拖动中同步更新）而不是
                            // 回调给的数值：事件成批到达时，受控的 value 可能
                            // 还停在上一帧。
                            onChangeEnd: (_) => _commit(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _clampIndex(int index) => index.clamp(0, widget.values.length - 1);

  /// TalkBack 上滑/下滑：移动一档并立即落盘（已在端点则不动、不写）。
  void _step(int delta) {
    final next = _clampIndex(_index + delta);
    if (next == _index) return;
    setState(() => _index = next);
    _commit();
  }

  /// 落盘：值没变就不写（点一下没拖动、拖回原档位都不写）。
  void _commit() {
    final value = widget.values[_index];
    if (value != widget.current) widget.onChanged(value);
  }
}
