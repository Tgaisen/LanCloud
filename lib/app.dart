import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/app_controller.dart';
import 'core/transfer/transfer_manager.dart';
import 'l10n/l10n.dart';
import 'ui/drive_page.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/profile_page.dart';
import 'ui/scroll_tint.dart';
import 'ui/transfers_page.dart';

class LanCloudApp extends StatelessWidget {
  const LanCloudApp({super.key});

  static const seed = Color(0xFF2E6BE6);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final seed = Color(app.settings.themeSeed);
    final oledDark = app.settings.oledBlack;
    ThemeData buildTheme(Brightness brightness) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
          ),
          scaffoldBackgroundColor:
              (brightness == Brightness.dark && oledDark) ? Colors.black : null,
          appBarTheme: AppBarTheme(
            scrolledUnderElevation: 3,
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
        );
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
      home: const RootShell(),
    );
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
    (icon: Icons.person_outline, selected: Icons.person),
  ];

  int _index = 0;
  bool _programmaticJump = false;
  late final PageController _pageController =
      PageController(initialPage: _index);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (i == _index) return;
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
    _index = context.read<AppController>().settings.launchPage == 'drive' ? 1 : 0;
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
      const HomePage(),
      const DrivePage(),
      const TransfersPage(),
      const ProfilePage(),
    ];
    // 底栏整体高度：悬浮样式含上下留白，用于 1:1 跟随滚动的收起距离
    final barHeight = app.settings.floatingNavBar ? 108.0 : 80.0;
    final keyed = KeyedSubtree(
      key: ValueKey('shell-${app.activeUid}'),
      // 横向滑动切换视图；设置里可关闭手势（只能点底栏切换）
      child: PageView(
        controller: _pageController,
        physics: app.settings.swipeTabs
            ? const PageScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        onPageChanged: (i) {
          // 程序化跳转经过中间页时保持指示器停留在目标，避免底栏按钮闪烁
          if (_programmaticJump && i != _index) return;
          setState(() => _index = i);
        },
        children: [
          for (final page in pages)
            ScrollTint(
              hideDistance: barHeight,
              onBarsHidden: (app.settings.hideTopBar || app.settings.hideBottomBar)
                  ? (progress) => app.barsHide.value = progress
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
          _ => l10n.tabProfile,
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
                            boxShadow: const [
                              BoxShadow(blurRadius: 14, color: Colors.black26),
                            ],
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
