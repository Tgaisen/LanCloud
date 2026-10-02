import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'core/app_controller.dart';
import 'core/agreements.dart';
import 'core/notifications.dart';
import 'core/share_inbox.dart';
import 'core/transfer/transfer_manager.dart';
import 'l10n/l10n.dart';
import 'ui/drive_page.dart';
import 'ui/first_run_terms.dart';
import 'ui/favorites_page.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/app_scroll.dart';
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
    ThemeData buildTheme(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      );
      return ThemeData(
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
          // Material Symbols：outlined、不填充、字重 400、层级 0、光学尺寸 24
          iconTheme: const IconThemeData(
            fill: 0,
            weight: 400,
            grade: 0,
            opticalSize: 24,
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
    }
    final mode = app.settings.themeMode;
    final language = app.settings.language;
    return MaterialApp(
      title: 'LanCloud',
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
      home: const AgreementGate(),
    );
  }
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

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard),
    (icon: Icons.folder_outlined, selected: Icons.folder),
    (
      icon: Icons.swap_vert_outlined,
      selected: Icons.swap_vert,
    ),
    (icon: Icons.star_border, selected: Icons.star_outline),
  ];

  int _index = 0;
  bool _programmaticJump = false;
  Size? _lastSize;
  // 横竖屏切换跨越 640px 布局阈值时，PageView 会在 Scaffold.body 与
  // Row/NavigationRail 两个不同深度的父级之间移动；ValueKey 无法跨父级
  // 保留元素，重建后像素偏移会落到错误的页。GlobalKey 可让 PageView 只
  // 移动、不重建。切换账号时更换 key，以保留重新挂载刷新页面的语义。
  String? _pageViewUid;
  late GlobalKey _pageViewKey = GlobalKey();
  late final PageController _pageController =
      PageController(initialPage: _index);

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
    context.read<AppController>().onSwitchTab = null;
    NotificationService.onOpenTransfers = null;
    SharedInbox.instance.onText = null;
    SharedInbox.instance.onFiles = null;
    SharedInbox.instance.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (i == _index) return;
    // 切换视图时把被收起的顶/底栏带动画调出来
    context.read<AppController>().animateBarsHide(0);
    setState(() => _index = i);
    _programmaticJump = true;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        if (mounted) _programmaticJump = false;
      });
    } else {
      _programmaticJump = false;
    }
  }

  int get _defaultIndex =>
      context.read<AppController>().settings.launchPage == 'drive' ? 1 : 0;

  @override
  void initState() {
    super.initState();
    context.read<AppController>().onSwitchTab = _goTo;
    NotificationService.onOpenTransfers = () => _goTo(2);
    SharedInbox.instance.onText = _handleSharedText;
    SharedInbox.instance.onFiles = _handleSharedFiles;
    SharedInbox.instance.attach();
    WidgetsBinding.instance.addPostFrameCallback((_) => _processPendingShare());
    if (NotificationService.pendingTransfers) {
      NotificationService.pendingTransfers = false;
      _index = 2;
    } else {
      _index = context.read<AppController>().settings.launchPage == 'drive'
          ? 1
          : 0;
    }
    // 记录初始视图，便于页面判断自己是否被激活
    context.read<AppController>().activeTab.value = _index;
  }

  String? _extractShareLink(String text) {
    final match = RegExp(
      r'https?://[^\s]*lanzou[a-z]*\.(com|cn)[^\s]*',
    ).firstMatch(text);
    if (match == null) return null;
    return match.group(0)!.replaceAll(RegExp(r'[),。，;；]+$'), '');
  }

  void _handleSharedText(String text) {
    final link = _extractShareLink(text);
    if (link == null || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.shareTargetUnsupported)),
      );
      return;
    }
    openShareSheet(context, initialLink: link);
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
    final defaultIndex = _defaultIndex;
    final transfers = context.read<TransferManager>();
    final active = _activeTasks;
    if (app.selectionMode) {
      app.onRequestExitSelection?.call();
      return false;
    }
    // 网盘视图：先让页面处理（返回上一级目录）
    if (_index == 1 && app.onDriveBack != null) {
      final handled = await app.onDriveBack!();
      if (handled) return false;
    }
    if (_index != defaultIndex) {
      _goTo(defaultIndex);
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
    }
    if (!app.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (app.activeUid == null) {
      return const LoginPage(firstRun: true);
    }

    final running = transfers.tasks
        .where((t) =>
            t.status == TransferStatus.running || t.status == TransferStatus.queued)
        .length;

    final pages = <Widget>[
      const HomePage(tabIndex: 0),
      const DrivePage(tabIndex: 1),
      const TransfersPage(tabIndex: 2),
      const FavoritesPage(tabIndex: 3),
    ];
    // 底栏整体高度：悬浮样式含上下留白，用于 1:1 跟随滚动的收起距离
    final barHeight = app.settings.floatingNavBar ? 108.0 : 80.0;
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
          // 视图真正切换后：恢复底栏并通知页面把折叠的顶栏调出来
          app.animateBarsHide(0);
          app.activeTab.value = i;
          setState(() => _index = i);
        },
        children: [
          for (final page in pages)
            ScrollTint(
              hideDistance: barHeight,
              readBarsHidden: () => app.barsHide.value,
              onBarsHidden: (app.settings.hideTopBar || app.settings.hideBottomBar)
                  ? app.setBarsHideFromScroll
                  : null,
              child: page,
            ),
        ],
      ),
    );

    Widget iconFor(int i, {required bool selected}) {
      final d = _destinations[i];
      final icon = Icon(selected ? d.selected : d.icon);
      if (i != 2 || running == 0) return icon;
      return Badge(label: Text('$running'), child: icon);
    }

    String labelFor(int i) => switch (i) {
          0 => l10n.tabHome,
          1 => l10n.tabDrive,
          2 => l10n.tabTransfers,
          3 => l10n.favorite,
          _ => l10n.tabHome,
        };

    final width = MediaQuery.sizeOf(context).width;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _handleBack();
        if (shouldExit && mounted) {
          await SystemNavigator.pop();
        }
      },
      child: width >= 640
          ? Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    extended: width >= 1080,
                    labelType:
                        width >= 1080 ? null : NavigationRailLabelType.all,
                    onDestinationSelected: _goTo,
                    destinations: [
                      for (var i = 0; i < _destinations.length; i++)
                        NavigationRailDestination(
                          icon: iconFor(i, selected: false),
                          selectedIcon: iconFor(i, selected: true),
                          label: Text(labelFor(i)),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: keyed),
                ],
              ),
            )
          : Scaffold(
              body: keyed,
              extendBody: app.settings.floatingNavBar,
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
                      maxHeight: barHeight,
                      child: child,
                    ),
                  ),
                ),
                child: Padding(
                  padding: app.settings.floatingNavBar
                      ? const EdgeInsets.only(top: 16)
                      : EdgeInsets.zero,
                  child: Container(
                    margin: app.settings.floatingNavBar
                        ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
                        : EdgeInsets.zero,
                    decoration: app.settings.floatingNavBar
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                          )
                        : null,
                    clipBehavior: app.settings.floatingNavBar
                        ? Clip.antiAlias
                        : Clip.none,
                    child: NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: (i) {
                        if (app.selectionMode) {
                          app.onRequestExitSelection?.call();
                        }
                        _goTo(i);
                      },
                      destinations: [
                        for (var i = 0; i < _destinations.length; i++)
                          NavigationDestination(
                            icon: iconFor(i, selected: false),
                            selectedIcon: iconFor(i, selected: true),
                            label: labelFor(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ),
    );
  }
}
