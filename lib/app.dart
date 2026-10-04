import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'core/app_controller.dart';
import 'core/agreements.dart';
import 'core/incoming_links.dart';
import 'core/lanzou_link.dart';
import 'core/notifications.dart';
import 'core/share_inbox.dart';
import 'core/transfer/transfer_manager.dart';
import 'l10n/l10n.dart';
import 'ui/drive_page.dart';
import 'ui/first_run_terms.dart';
import 'ui/favorites_page.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/profile_page.dart';
import 'ui/app_scroll.dart';
import 'ui/common.dart';
import 'ui/scroll_tint.dart';
import 'ui/share_page.dart';
import 'ui/transfers_page.dart';
import 'ui/app_icons.dart';

class LanCloudApp extends StatelessWidget {
  const LanCloudApp({super.key});

  static const seed = Color(0xFF2E6BE6);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final seed = Color(app.settings.themeSeed);
    final oledDark = app.settings.oledBlack;
    final useDynamicColor = app.settings.dynamicColor;
    final mode = app.settings.themeMode;
    final language = app.settings.language;
    // MD3 动态取色：系统壁纸取色（Android 12+），不支持时返回 null。
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ThemeData buildTheme(Brightness brightness) => buildLanCloudTheme(
              brightness: brightness,
              seed: seed,
              oledDark: oledDark,
              dynamicScheme: useDynamicColor
                  ? (brightness == Brightness.dark
                      ? darkDynamic
                      : lightDynamic)
                  : null,
            );
        return MaterialApp(
          // 系统「最近任务」里的应用名（桌面图标名由 Android 资源 app_name 决定，
          // 任务卡片这里是 Flutter 的 Title 设置的，要跟着语言走）
          onGenerateTitle: (context) => context.l10n.appName,
          debugShowCheckedModeBanner: false,
          locale: language == 'zh'
              ? const Locale('zh')
              : language == 'en'
                  ? const Locale('en')
                  : null,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode == 'light'
              ? ThemeMode.light
              : mode == 'dark'
                  ? ThemeMode.dark
                  : ThemeMode.system,
          // 全局 BouncingScrollPhysics（网盘页同款）
          scrollBehavior: const AppScrollBehavior(),
          // 系统栏（状态栏 / 导航栏）样式跟随主题明暗：
          // Android 15+ 导航栏强制透明，能调的只有图标明暗与是否加系统遮罩。
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: systemUiOverlayStyleFor(Theme.of(context).brightness),
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AgreementGate(),
        );
      },
    );
  }
}

/// 全局系统栏样式：状态栏、导航栏都透明，图标明暗随主题，
/// 并关掉系统给透明导航栏垫的半透明遮罩（否则看着不是真透明）。
SystemUiOverlayStyle systemUiOverlayStyleFor(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 应用主题（Material 3 + MD3E 细节）。抽出来便于测试。
///
/// 注意 [ThemeData.iconTheme] 必须保留默认图标颜色：如果传入一个
/// "只有字重 / 填充轴、没有颜色"的 IconThemeData，IconButton 解析到的
/// 前景色会是 null，深色模式下图标会被画成黑色。
ThemeData buildLanCloudTheme({
  required Brightness brightness,
  required Color seed,
  required bool oledDark,
  ColorScheme? dynamicScheme,
}) {
  // 动态取色（Android 12+）优先，取不到时回退到主题色。
  //
  // 注意：dynamic_color 给的色板只包含旧版角色，surfaceContainer /
  // surfaceContainerHigh / surfaceDim 这些 MD3 新角色没赋值，读取时会退化成
  // surface，于是背景、卡片、导航区全变成一个颜色（看起来处处纯白）。
  // 这里用系统取到的主色重新生成完整色板：保留壁纸色相，同时补齐所有角色。
  final scheme = ColorScheme.fromSeed(
    seedColor: dynamicScheme?.primary ?? seed,
    brightness: brightness,
  );
  final theme = ThemeData(
          colorScheme: scheme,
          scaffoldBackgroundColor:
              (brightness == Brightness.dark && oledDark) ? Colors.black : null,
          appBarTheme: AppBarTheme(
            scrolledUnderElevation: 0,
            backgroundColor:
                (brightness == Brightness.dark && oledDark) ? Colors.black : null,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: brightness == Brightness.dark
                  ? Brightness.dark
                  : Brightness.light,
            ),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          // MD3 扁平化：控件统一去阴影
          cardTheme: const CardThemeData(elevation: 0),
          navigationBarTheme: const NavigationBarThemeData(elevation: 0),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            elevation: 0,
            focusElevation: 0,
            hoverElevation: 0,
            highlightElevation: 0,
            disabledElevation: 0,
          ),
          // MD3 Expressive 按钮组（connected）：细描边 + 圆角容器 + 选中勾选
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              side: WidgetStatePropertyAll(
                BorderSide(color: scheme.outlineVariant),
              ),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.padded,
              animationDuration: const Duration(milliseconds: 240),
            ),
          ),
        );
  // Material Symbols 可变轴：weight 400 / grade 0 / optical size 24（fill 0）。
  // 必须用 copyWith 保留主题默认图标颜色——直接传一个"只有轴、没有颜色"的
  // IconThemeData 会让 IconButton 前景色变成 null，深色模式下图标画成黑色。
  return theme.copyWith(
    iconTheme: theme.iconTheme.copyWith(
      fill: 0,
      weight: 400,
      grade: 0,
      opticalSize: 24,
    ),
  );
}

/// 首次启动先请求同意用户协议与隐私政策；不同意则退出应用。
class AgreementGate extends StatefulWidget {
  const AgreementGate({super.key});

  @override
  State<AgreementGate> createState() => _AgreementGateState();
}

class _AgreementGateState extends State<AgreementGate> {
  bool _checked = false;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    Agreements.accepted().then((value) {
      if (!mounted) return;
      setState(() {
        _checked = true;
        _accepted = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_accepted) {
      return FirstRunTerms(
        onAccepted: () => setState(() => _accepted = true),
      );
    }
    return const RootShell();
  }
}

/// 返回手势能否交给系统处理（系统才会播放退回桌面的预测性返回动画）。
///
/// 只有「默认视图 + 非多选 + 没有进行中的传输 + 网盘页没有可返回的层级」时
/// 才交给系统；其余情况必须由 Flutter 拦下来做应用内导航（切默认视图 /
/// 返回上级目录 / 退出多选）或传输中的退出确认，此时按官方语义不做预测动画。
///
/// [selectionMode] 由 AppController 统一维护：网盘 / 传输 / 收藏页的多选
/// 都会把它置为 true，所以这三页（在底栏显示时）的多选都会被拦下来。
@visibleForTesting
bool canHandBackToSystem({
  required bool selectionMode,
  required bool hasActiveTransfers,
  required bool atDefaultView,
  required bool driveCanHandleBack,
}) =>
    !selectionMode &&
    !hasActiveTransfers &&
    atDefaultView &&
    !driveCanHandleBack;

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  /// 视图 id：0 首页 / 1 网盘 / 2 传输 / 3 收藏 / 4 我的。
  /// id 固定不变，底栏顺序由 [_ids] 决定（传输、收藏可隐藏）。
  static const _viewHome = 0;
  static const _viewDrive = 1;
  static const _viewTransfers = 2;
  static const _viewFavorites = 3;
  static const _viewProfile = 4;

  /// 当前底栏包含的视图 id（顺序即底栏顺序）。
  List<int> _ids = const <int>[];
  bool _navConfigPending = false;

  int _index = 0;
  bool _programmaticJump = false;
  Size? _lastSize;
  // 横竖屏切换跨越 640px 布局阈值时，PageView 会在 Scaffold.body 与
  // Row/NavigationRail 两个不同深度的父级之间移动；ValueKey 无法跨父级
  // 保留元素，重建后像素偏移会落到错误的页。GlobalKey 可让 PageView 只
  // 移动、不重建。切换账号时更换 key，以保留重新挂载刷新页面的语义。
  String? _pageViewUid;
  late GlobalKey _pageViewKey = GlobalKey();
  late PageController _pageController = PageController(initialPage: _index);
  bool _pagerSyncPending = false;
  /// 连续重建分页器的次数：一直连不上就放弃，避免每帧重建。
  int _pagerRebuilds = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 旋转后视口尺寸变化，PageView 的像素偏移会对应到错误的页，
    // 这里在布局结束后校正回当前标签，避免“底栏指向原视图但内容回到首页”。
    final size = MediaQuery.sizeOf(context);
    if (_lastSize != null && _lastSize != size) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_index);
        }
      });
    }
    _lastSize = size;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<AppController>().onSwitchTab = null;
    NotificationService.onOpenTransfers = null;
    SharedInbox.instance.onText = null;
    SharedInbox.instance.onFiles = null;
    SharedInbox.instance.dispose();
    IncomingLinks.instance.onLink = null;
    IncomingLinks.instance.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 当前底栏显示项：首页 / 网盘 + （可选的）传输 / 收藏 + 我的。
  List<int> _enabledIds(AppController app) => <int>[
        _viewHome,
        _viewDrive,
        if (app.settings.navShowTransfers) _viewTransfers,
        if (app.settings.navShowFavorites) _viewFavorites,
        _viewProfile,
      ];

  /// 各视图顶栏高度：大屏布局用它决定圆角内容卡片的起点。
  double _topBarHeightFor(int viewId) {
    final top = MediaQuery.paddingOf(context).top;
    return switch (viewId) {
      _viewDrive => top + kToolbarHeight + kDrivePathBarHeight,
      _viewTransfers => top + kToolbarHeight + kTransfersTabBarHeight,
      _ => top + kToolbarHeight,
    };
  }

  Widget _pageFor(int id) => switch (id) {
        _viewHome => const HomePage(tabIndex: _viewHome),
        _viewDrive => const DrivePage(tabIndex: _viewDrive),
        _viewTransfers => const TransfersPage(tabIndex: _viewTransfers),
        _viewFavorites => const FavoritesPage(tabIndex: _viewFavorites),
        _ => const ProfilePage(tabIndex: _viewProfile),
      };

  IconData _iconFor(int id, {required bool selected}) => switch (id) {
        _viewHome => selected ? Icons.dashboard : Icons.dashboard_outlined,
        _viewDrive => selected ? Icons.folder : Icons.folder_outlined,
        _viewTransfers => selected ? Icons.swap_vert : Icons.swap_vert_outlined,
        _viewFavorites => selected ? Icons.star_outline : Icons.star_border,
        _ => selected ? Icons.person : Icons.person_outline,
      };

  String _labelFor(int id, AppLocalizations l10n) => switch (id) {
        _viewHome => l10n.tabHome,
        _viewDrive => l10n.tabDrive,
        _viewTransfers => l10n.tabTransfers,
        _viewFavorites => l10n.favorite,
        _ => l10n.tabProfile,
      };

  /// 打开某个视图：在底栏显示时切换到对应页，否则作为新页面打开。
  void _goTo(int viewId) {
    final i = _ids.indexOf(viewId);
    if (i < 0) {
      _openView(viewId);
      return;
    }
    if (i == _index) return;
    // 切换视图（含底栏、侧栏、程序化跳转）时退出多选
    final app = context.read<AppController>();
    if (app.selectionMode) app.onRequestExitSelection?.call();
    // 切换视图时收起输入法，避免返回该页时键盘又弹出来
    FocusManager.instance.primaryFocus?.unfocus();
    // 切换视图时把被收起的顶/底栏带动画调出来
    app.animateBarsHide(0);
    setState(() => _index = i);
    _programmaticJump = true;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        if (!mounted) return;
        _programmaticJump = false;
        // 若分页器因为重新挂载而没有真正翻页，这里把它拉回来
        _schedulePagerSync();
      });
    } else {
      _programmaticJump = false;
      _schedulePagerSync();
    }
  }

  /// 未显示在底栏的视图：以独立页面打开同样的界面。
  void _openView(int viewId) {
    Navigator.of(context).push(
      // 大屏（横屏 / 平板）下独立打开的标签页也套 MD3E 卡片：
      // 顶栏高度与外壳里一致，顶栏收起进度共用 app.topBarHide
      MaterialPageRoute<void>(
        builder: (_) => Md3ePageFrame(
          topBarHeight: _topBarHeightFor(viewId),
          hide: context.read<AppController>().topBarHide,
          child: _pageFor(viewId),
        ),
      ),
    );
  }

  /// 底栏显示项变化：下一帧按新页序重建，尽量停留在当前视图。
  void _syncNavConfig(List<int> ids) {
    if (_navConfigPending) return;
    _navConfigPending = true;
    final target = List<int>.unmodifiable(ids);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navConfigPending = false;
      if (!mounted) return;
      final app = context.read<AppController>();
      final current =
          _ids.isEmpty ? target.first : _ids[_index.clamp(0, _ids.length - 1)];
      final next = target.contains(current) ? target.indexOf(current) : 0;
      setState(() {
        _ids = target;
        _index = next;
      });
      app.activeTab.value = target[next];
      if (_pageController.hasClients) _pageController.jumpToPage(next);
    });
  }

  /// 兜底：分页器被重新挂载（换账号、切换 loading 页）后可能停在初始页，
  /// 与底栏高亮错位时把它拉回当前视图，避免「内容不动、底栏点了没反应」。
  void _schedulePagerSync() {
    if (_pagerSyncPending) return;
    _pagerSyncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pagerSyncPending = false;
      if (!mounted || _programmaticJump) return;
      // 控制器没连上分页器（换账号 / 重新挂载后失效）：整体重建一次
      if (!_pageController.hasClients) {
        if (_pagerRebuilds >= 3) return;
        _pagerRebuilds++;
        _rebuildPager();
        return;
      }
      _pagerRebuilds = 0;
      final position = _pageController.position;
      // 用户滑动 / 补间动画进行中不打断
      if (position.isScrollingNotifier.value) return;
      final page = _pageController.page?.round();
      if (page != null && page != _index) {
        _pageController.jumpToPage(_index);
      }
    });
  }

  /// 兜底：用新的控制器重建分页器，并直接停在当前视图。
  void _rebuildPager() {
    final previous = _pageController;
    setState(() {
      _pageController = PageController(initialPage: _index);
      _pageViewKey = GlobalKey();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  int get _defaultViewId =>
      context.read<AppController>().settings.launchPage == 'drive'
          ? _viewDrive
          : _viewHome;

  /// 当前视图 id（底栏配置还没就绪时按首页算）。
  int get _currentViewId => _ids.isEmpty ? _viewHome : _ids[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final app = context.read<AppController>();
    _ids = _enabledIds(app);
    app.onSwitchTab = _goTo;
    NotificationService.onOpenTransfers = () => _goTo(_viewTransfers);
    SharedInbox.instance.onText = _handleSharedText;
    SharedInbox.instance.onFiles = _handleSharedFiles;
    SharedInbox.instance.attach();
    IncomingLinks.instance.onLink = _handleIncomingLink;
    IncomingLinks.instance.attach();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processPendingShare();
      final url = IncomingLinks.instance.pending;
      IncomingLinks.instance.pending = null;
      if (url != null) _handleIncomingLink(url);
      _checkClipboard();
      if (_pendingStartView != null) {
        final view = _pendingStartView!;
        _pendingStartView = null;
        _goTo(view);
      }
    });
    if (NotificationService.pendingTransfers) {
      NotificationService.pendingTransfers = false;
      _pendingStartView = _viewTransfers;
    }
    _index = _ids.indexOf(_defaultViewId).clamp(0, _ids.length - 1);
    // 记录初始视图，便于页面判断自己是否被激活
    app.activeTab.value = _ids[_index];
  }

  /// 冷启动时要额外打开的视图（例如从传输通知进来），可能在底栏外。
  int? _pendingStartView;

  void _handleSharedText(String text) {
    final link = LanzouLink.parse(text);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.shareTargetUnsupported)),
      );
      return;
    }
    openShareSheet(context, initialLink: link.url, initialPwd: link.pwd);
  }

  /// 外部链接（点开蓝奏云分享链接默认交给本应用）。
  void _handleIncomingLink(String url) {
    final link = LanzouLink.parse(url);
    if (link == null) return;
    _lastClipboardText = url;
    openShareSheet(context, initialLink: link.url, initialPwd: link.pwd);
  }

  /// 已处理过的剪贴板内容，避免同一条链接反复提示。
  String? _lastClipboardText;

  /// 回到前台时看看剪贴板里有没有蓝奏云分享链接（类似淘口令）。
  Future<void> _checkClipboard() async {
    if (!mounted) return;
    final app = context.read<AppController>();
    if (!app.settings.clipboardLinkPrompt) return;
    // 没有账号时（首次启动 / 登录页）不打扰
    if (app.activeUid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // 回到前台的一瞬间剪贴板可能还读不到，稍等一下再取
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text?.trim();
    } catch (_) {
      return;
    }
    if (text == null || text.isEmpty || text == _lastClipboardText) return;
    _lastClipboardText = text;
    final link = LanzouLink.parse(text);
    if (link == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.clipboardLinkFound),
        action: SnackBarAction(
          label: l10n.open,
          onPressed: () {
            if (!mounted) return;
            openShareSheet(
              context,
              initialLink: link.url,
              initialPwd: link.pwd,
            );
          },
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  Future<void> _handleSharedFiles(List<String> files) async {
    final app = context.read<AppController>();
    final client = app.client;
    if (client == null || app.activeUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.notLoggedIn)),
      );
      return;
    }
    final target = await showFolderPicker(
      context,
      client: client,
      confirmLabel: context.l10n.uploadHere,
      initialName: files.length == 1 ? p.basename(files.first) : null,
    );
    if (target == null || !mounted) return;
    final transfers = context.read<TransferManager>();
    var added = 0;
    for (final path in files) {
      final editedName = target.fileName;
      final name = files.length == 1 &&
              editedName != null &&
              editedName.isNotEmpty
          ? editedName
          : p.basename(path);
      transfers.addUpload(
        name: name,
        folderId: target.folderId,
        path: path,
      );
      added += 1;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.shareReceivedFiles(added))),
    );
  }

  void _processPendingShare() {
    final inbox = SharedInbox.instance;
    final text = inbox.pendingText;
    inbox.pendingText = null;
    if (text != null && text.isNotEmpty) {
      _handleSharedText(text);
      return;
    }
    final files = inbox.pendingFiles;
    inbox.pendingFiles = [];
    if (files.isNotEmpty) _handleSharedFiles(files);
  }

  List<TransferTask> get _activeTasks => context
      .read<TransferManager>()
      .tasks
      .where((t) =>
          t.status == TransferStatus.running || t.status == TransferStatus.queued)
      .toList();

  Future<bool> _handleBack() async {
    final app = context.read<AppController>();
    final defaultView = _defaultViewId;
    final transfers = context.read<TransferManager>();
    final active = _activeTasks;
    if (app.selectionMode) {
      app.onRequestExitSelection?.call();
      return false;
    }
    final currentView = _currentViewId;
    // 网盘视图：先让页面处理（返回上一级目录）
    if (currentView == _viewDrive && app.onDriveBack != null) {
      final handled = await app.onDriveBack!();
      if (handled) return false;
    }
    if (currentView != defaultView) {
      _goTo(defaultView);
      return false;
    }
    if (active.isEmpty) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.exitTitle),
        content: Text(context.l10n.exitMessage(active.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.keepTransferring),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.exitAndCancel),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    for (final task in active) {
      transfers.cancel(task.id);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final transfers = context.watch<TransferManager>();
    final l10n = context.l10n;
    NotificationService.i18n = l10n;
    if (app.activeUid != _pageViewUid) {
      _pageViewUid = app.activeUid;
      _pageViewKey = GlobalKey();
      // 换账号会重建分页器：新控制器直接以当前视图为初始页，
      // 否则会回到首页并与底栏高亮错位（点当前的底栏项没反应）。
      final previous = _pageController;
      _pageController = PageController(initialPage: _index);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    if (!app.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (app.activeUid == null) {
      return const LoginPage(firstRun: true);
    }
    // 底栏显示项变化时，下一帧按新页序重建
    if (_ids.isEmpty) {
      _ids = _enabledIds(app);
    } else {
      final ids = _enabledIds(app);
      if (!listEquals(ids, _ids)) {
        _syncNavConfig(ids);
      } else {
        _schedulePagerSync();
      }
    }

    final running = transfers.tasks
        .where((t) =>
            t.status == TransferStatus.running || t.status == TransferStatus.queued)
        .length;

    // 底栏整体高度：悬浮样式含上下留白，用于 1:1 跟随滚动的收起距离，
    // 再加上系统手势区（导航栏）的高度。普通底栏由 NavigationBar 自己
    // 用 SafeArea 把这份内边距垫在内容下方；悬浮样式则算进下留白，
    // 让 80dp 高的胶囊浮在系统导航栏上方。两种样式外层都不能把高度写死，
    // 否则这份内边距会从内容里扣，图标和文字被压扁。
    final systemPadding = MediaQuery.paddingOf(context);
    final bottomInset = systemPadding.bottom;
    final barHeight =
        (app.settings.floatingNavBar ? 108.0 : 80.0) + bottomInset;
    final keyed = KeyedSubtree(
      key: ValueKey('shell-${app.activeUid}'),
      // 横向滑动切换视图；设置里可关闭手势（只能点底栏切换）
      child: PageView(
        key: _pageViewKey,
        controller: _pageController,
        physics: app.settings.swipeTabs
            ? const PageScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        onPageChanged: (i) {
          // 程序化跳转经过中间页时保持指示器停留在目标，避免底栏按钮闪烁
          if (_programmaticJump && i != _index) return;
          // 横滑切换视图时同样退出多选
          if (app.selectionMode) app.onRequestExitSelection?.call();
          FocusManager.instance.primaryFocus?.unfocus();
          // 视图真正切换后：恢复底栏并通知页面把折叠的顶栏调出来
          app.animateBarsHide(0);
          app.activeTab.value = _ids[i];
          setState(() => _index = i);
        },
        children: [
          for (final id in _ids)
            ScrollTint(
              key: ValueKey('view-$id'),
              hideDistance: barHeight,
              readBarsHidden: () => app.barsHide.value,
              onBarsHidden: (app.settings.hideTopBar || app.settings.hideBottomBar)
                  ? app.setBarsHideFromScroll
                  : null,
              child: _pageFor(id),
            ),
        ],
      ),
    );

    Widget iconFor(int viewId, {required bool selected}) {
      final icon = Icon(_iconFor(viewId, selected: selected));
      if (viewId != _viewTransfers || running == 0) return icon;
      return Badge(label: Text('$running'), child: icon);
    }

    final width = MediaQuery.sizeOf(context).width;
    final scheme = Theme.of(context).colorScheme;
    // 大屏（MD3E）：侧栏等导航区用 surfaceContainer，主视图是圆角的 surface 卡片
    final bodyColor = Theme.of(context).scaffoldBackgroundColor;
    final floatingNav = app.settings.floatingNavBar;
    final navBar = NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (pos) {
        if (app.selectionMode) {
          app.onRequestExitSelection?.call();
        }
        _goTo(_ids[pos]);
      },
      destinations: [
        for (final id in _ids)
          NavigationDestination(
            icon: iconFor(id, selected: false),
            selectedIcon: iconFor(id, selected: true),
            label: _labelFor(id, l10n),
          ),
      ],
    );
    // 返回手势何时交给系统：只有「默认视图 + 没有要拦截的目标」才置
    // canPop=true，系统才会播放退回桌面的预测性返回动画（官方语义：
    // PopScope.canPop=false 时不做预测动画）。其余情况（多选 / 网盘
    // 子目录或搜索 / 非默认视图 / 传输中的退出确认）交给 _handleBack 处理。
    final currentView = _currentViewId;
    return ValueListenableBuilder<bool>(
      valueListenable: app.driveCanHandleBack,
      builder: (context, driveCanHandleBack, child) {
        final canPop = canHandBackToSystem(
          selectionMode: app.selectionMode,
          hasActiveTransfers: running > 0,
          atDefaultView: currentView == _defaultViewId,
          driveCanHandleBack: currentView == _viewDrive && driveCanHandleBack,
        );
        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldExit = await _handleBack();
            if (shouldExit && mounted) {
              await SystemNavigator.pop();
            }
          },
          child: child!,
        );
      },
      child: width >= kLargeLayoutBreakpoint
          ? Scaffold(
              backgroundColor: scheme.surfaceContainer,
              body: Row(
                children: [
                  NavigationRail(
                    backgroundColor: Colors.transparent,
                    selectedIndex: _index,
                    // 统一用非展开样式：图标在上、文字在下，栏宽 72dp。
                    // 展开样式（extended）要 256dp，对这几个短标题太宽了。
                    extended: false,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (i) => _goTo(_ids[i]),
                    destinations: [
                      for (final id in _ids)
                        NavigationRailDestination(
                          icon: iconFor(id, selected: false),
                          selectedIcon: iconFor(id, selected: true),
                          label: Text(_labelFor(id, l10n)),
                        ),
                    ],
                  ),
                  // 主视图：顶栏留在导航区（surfaceContainer），
                  // 圆角的 surface 卡片从顶栏下方开始，页面背景透明；
                  // 顶栏收起时卡片顶边跟着上移，内容始终被顶栏或卡片盖住
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: app.topBarHide,
                      builder: (context, hide, _) {
                        final t =
                            app.settings.hideTopBar ? hide.clamp(0.0, 1.0) : 0.0;
                        return Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: _topBarHeightFor(_ids[_index]) * (1 - t),
                              // 卡片四周的 8dp 留白之外，再让开系统导航栏：
                              // 横屏时它可能在底部（手势导航）或在右侧（三键导航），
                              // 否则卡片底部/右侧会被系统栏压住
                              right: 8 + systemPadding.right,
                              bottom: 8 + systemPadding.bottom,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: ColoredBox(color: bodyColor),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: 0,
                              right: 8 + systemPadding.right,
                              bottom: 8 + systemPadding.bottom,
                              // 卡片已经按 left/right/bottom inset 让过位了，
                              // 页面内（AppBar / SafeArea / Scrollbar）不要再让一次
                              child: MediaQuery.removePadding(
                                context: context,
                                removeLeft: true,
                                removeRight: true,
                                removeBottom: true,
                                child: keyed,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          : Scaffold(
              body: keyed,
              // 正文绘制到底栏下方：滑动时内容从底栏后穿过，
              // 底栏跟随滚动下沉 / 收起时正文也不会跟着重排。
              extendBody: true,
              // 底栏跟随滚动按比例下沉；完全收起后腾出布局空间
              bottomNavigationBar: ValueListenableBuilder<double>(
                valueListenable: app.barsHide,
                builder: (context, hide, child) => SizedBox(
                  height: app.settings.hideBottomBar
                      ? barHeight * (1 - hide)
                      : barHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      // minHeight 必须等于完整高度：否则底栏会被压扁（内容缩放）而不是滑出
                      minHeight: barHeight,
                      maxHeight: barHeight,
                      child: child,
                    ),
                  ),
                ),
                child: Padding(
                  padding: floatingNav
                      ? const EdgeInsets.only(top: 16)
                      : EdgeInsets.zero,
                  child: Container(
                    margin: floatingNav
                        // 底部留白要加上系统导航栏的高度：胶囊本身保持
                        // 80dp 浮在导航栏上方，而不是把导航栏那段也算进胶囊
                        // （否则胶囊下沿会拖出一截空白色）。
                        ? EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset)
                        : EdgeInsets.zero,
                    decoration: floatingNav
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                          )
                        : null,
                    clipBehavior: floatingNav ? Clip.antiAlias : Clip.none,
                    // 悬浮样式把系统手势区的内边距从胶囊里摘掉，改由上面
                    // 的下留白承担；普通底栏仍由 NavigationBar 自己垫在内容下方。
                    // top 也要去掉：这里不再经过 Scaffold 的底栏槽位（槽位会
                    // 去掉顶部内边距），否则状态栏高度会被 SafeArea 垫进胶囊。
                    child: floatingNav
                        ? MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            removeBottom: true,
                            child: navBar,
                          )
                        : navBar,
                  ),
                ),
              ),
          ),
    );
  }
}
