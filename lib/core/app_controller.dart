import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'api/lanzou_client.dart';
import 'api/lanzou_client_registry.dart';
import 'account_state.dart';
import 'account_login.dart';
import 'account_session.dart';
import 'app_log.dart';
import 'app_runtime_state.dart';
import 'data/account_store.dart';
import 'data/app_db.dart';
import 'data/settings_store.dart';
import 'data/secure_storage.dart';
import 'download_directory_settings_state.dart';
import 'drive_state.dart';
import 'drive_cache.dart';
import 'cache_page_settings_state.dart';
import 'dynamic_color_support.dart';
import 'navigation_state.dart';
import 'navigation_appearance_settings_state.dart';
import 'notification_settings_state.dart';
import 'list_home_settings_state.dart';
import 'language_clipboard_settings_state.dart';
import 'saf_storage.dart';
import 'settings_state.dart';
import 'system_motion.dart';
import 'theme_settings_state.dart';
import 'transfer_connection_settings_state.dart';
import 'update/update_settings_state.dart';

export 'drive_state.dart' show DriveLocation;

class AppController extends ChangeNotifier {
  AppController({
    NavigationState? navigation,
    DriveState? drive,
    AccountState? accountState,
    SettingsState? settingsState,
    AppRuntimeState? runtimeState,
  }) : navigation = navigation ?? NavigationState(),
       drive = drive ?? DriveState(),
       accountState = accountState ?? AccountState(),
       settingsState = settingsState ?? SettingsState(),
       runtimeState = runtimeState ?? AppRuntimeState() {
    updateSettings = UpdateSettingsState(settings);
    notificationSettings = NotificationSettingsState(settings);
    navigationAppearanceSettings = NavigationAppearanceSettingsState(
      settings,
      navigation: this.navigation,
      reduceMotion: () => motionReduced,
    );
    themeSettings = ThemeSettingsState(settings);
    transferConnectionSettings = TransferConnectionSettingsState(settings);
    listHomeSettings = ListHomeSettingsState(
      settings,
      trimRecents: db.trimRecents,
      activeUid: () => activeUid,
    );
    languageClipboardSettings = LanguageClipboardSettingsState(settings);
    cachePageSettings = CachePageSettingsState(settings, this.drive.cache);
    downloadDirectorySettings = DownloadDirectorySettingsState(settings);
    this.navigation.addListener(notifyListeners);
    navigationAppearanceSettings.revision.addListener(notifyListeners);
    themeSettings.revision.addListener(notifyListeners);
    languageClipboardSettings.revision.addListener(notifyListeners);
    listHomeSettings.revision.addListener(notifyListeners);
    downloadDirectorySettings.revision.addListener(notifyListeners);
    this.accountState.addListener(notifyListeners);
  }

  final AccountState accountState;
  final SettingsState settingsState;
  final AppRuntimeState runtimeState;
  late final UpdateSettingsState updateSettings;
  late final NotificationSettingsState notificationSettings;
  late final NavigationAppearanceSettingsState navigationAppearanceSettings;
  late final ThemeSettingsState themeSettings;
  late final TransferConnectionSettingsState transferConnectionSettings;
  late final ListHomeSettingsState listHomeSettings;
  late final LanguageClipboardSettingsState languageClipboardSettings;
  late final CachePageSettingsState cachePageSettings;
  late final DownloadDirectorySettingsState downloadDirectorySettings;

  AccountStore get accounts => accountState.store;

  SettingsStore get settings => settingsState.store;

  final AppDb db = AppDb.instance;
  DriveCache get driveCache => drive.cache;
  final NavigationState navigation;
  final DriveState drive;

  final LanzouClientRegistry clientRegistry = LanzouClientRegistry();
  late final AccountLogin accountLogin = AccountLogin(
    accountState: accountState,
    clients: clientRegistry,
    driveCache: driveCache,
  );
  late final AccountSession accountSession = AccountSession(
    accountState: accountState,
    clients: clientRegistry,
    driveCache: driveCache,
    db: db,
  );

  bool get ready => runtimeState.ready.value;
  set ready(bool value) => runtimeState.ready.value = value;

  bool get secureStorageNeedsReauthentication =>
      runtimeState.secureStorageNeedsReauthentication.value;
  set secureStorageNeedsReauthentication(bool value) =>
      runtimeState.secureStorageNeedsReauthentication.value = value;

  bool get selectionMode => navigation.selectionMode;

  VoidCallback? get onRequestExitSelection =>
      navigation.onRequestExitSelection;
  set onRequestExitSelection(VoidCallback? handler) =>
      navigation.onRequestExitSelection = handler;

  /// 网盘页注册的返回处理：返回 true 表示已消费（例如返回上一级目录）。
  Future<bool> Function()? get onDriveBack => navigation.onDriveBack;
  set onDriveBack(Future<bool> Function()? handler) =>
      navigation.onDriveBack = handler;

  /// 「我的」页注册的返回处理：返回 true 表示已消费（退出搜索 / 关闭二级设置页）。
  /// 外壳在「非默认视图 → 回默认视图」的兜底之前先问它。
  Future<bool> Function()? get onProfileBack => navigation.onProfileBack;
  set onProfileBack(Future<bool> Function()? handler) =>
      navigation.onProfileBack = handler;

  /// 网盘页当前是否需要自己消费返回手势（多选 / 搜索 / 已在子目录），
  /// 由外壳里的 [DrivePage] 实时上报。RootShell 用它决定返回手势交给系统
  /// （系统才会播放退回桌面的预测性返回动画）还是由 Flutter 拦截。
  ValueNotifier<bool> get driveCanHandleBack => navigation.driveCanHandleBack;

  void setSelectionMode(bool value) => navigation.setSelectionMode(value);

  Future<void> init() async {
    await _inspectSecureStorageUpgrade();
    await accounts.load();
    await settings.load();
    _applyRuntimeSettings();
    await driveCache.bindAccount(accounts.activeUid);
    ready = true;
    notifyListeners();
    _refreshActiveAccountInfo();
    // 设备支持动态取色且用户还没选过：默认开启（之后尊重用户选择）
    unawaited(autoEnableDynamicColorIfSupported());
  }

  /// v11 会移除旧密文和旧加密后端的读取能力。必须在账号存储第一次读取前
  /// 检查；不可迁移时账号存储会回到空状态，外壳随后稳定落到登录页。
  Future<void> _inspectSecureStorageUpgrade() async {
    try {
      final status = await checkSecureStorageUpgradeOnce();
      if (status == null) return;
      secureStorageNeedsReauthentication =
          status.hasDataLoss || status.willDiscardOnNextAccess;
      if (secureStorageNeedsReauthentication) {
        AppLog.instance.log('secure_storage', '需要重新登录：$status');
      }
    } catch (error, stack) {
      // 状态检查失败不阻断启动；真正的读取仍有插件自身兜底。
      AppLog.instance.error('secure_storage', error, stack);
    }
  }

  /// 首次启动时按设备支持情况自动开启动态取色。
  /// 只影响「用户从未手动设置过」的情况；用户关掉后不会再被打开。
  /// 抽成公开方法便于单独测试（不依赖 [init] 里的账号存储等）。
  Future<void> autoEnableDynamicColorIfSupported() async {
    if (settings.dynamicColorChosen || settings.dynamicColor) return;
    if (!await DynamicColorSupport.isSupported()) return;
    // 探测期间用户可能已经手动改过
    if (settings.dynamicColorChosen || settings.dynamicColor) return;
    await setDynamicColor(true);
  }

  void _applyRuntimeSettings() {
    LanzouClient.requestInterval = Duration(
      milliseconds: settings.requestInterval,
    );
    LanzouClient.apiBase = lanzouApiBaseForHost(settings.apiHost);
    LanzouClient.userAgent = settings.userAgent;
    LanzouClient.uploadPath = settings.uploadPath;
    // 设置页「全局动画」：同步给 SystemMotion，根 widget 监听它整树重建，
    // 各处 reduceMotionOf() 立刻按新值生效（备份恢复走同一入口）。
    SystemMotion.motionMode.value = settings.motionMode;
  }

  /// 备份恢复后重新读取账号与设置，并重建网盘客户端。
  Future<void> reloadFromStorage() async {
    await accounts.load();
    if (accounts.accounts.isNotEmpty) {
      secureStorageNeedsReauthentication = false;
    }
    await settings.load();
    _applyRuntimeSettings();
    themeSettings.refresh();
    languageClipboardSettings.refresh();
    clientRegistry.clearAccounts();
    await driveCache.bindAccount(accounts.activeUid);
    if (!settings.cacheFolders) driveCache.clear();
    notifyListeners();
    _refreshActiveAccountInfo();
  }

  Future<void> setRequestInterval(int ms) async {
    await transferConnectionSettings.setRequestInterval(ms);
    notifyListeners();
  }

  Future<void> setApiHost(String host) async {
    await transferConnectionSettings.setApiHost(host);
    notifyListeners();
  }

  Future<void> setUserAgent(String value) async {
    await transferConnectionSettings.setUserAgent(value);
    notifyListeners();
  }

  Future<void> setUploadPath(String value) async {
    await transferConnectionSettings.setUploadPath(value);
    notifyListeners();
  }

  Future<void> setSwipeTabs(bool value) async {
    await navigationAppearanceSettings.setSwipeTabs(value);
  }

  /// 切换更新通道；检测结果由 Riverpod 更新控制器在同一交互中清理。
  Future<void> setUpdateChannel(String value) async {
    if (await updateSettings.setChannel(value)) notifyListeners();
  }

  Future<void> setUpdateAutoCheck(bool value) async {
    await updateSettings.setAutoCheck(value);
    notifyListeners();
  }

  /// 设置固定路径的下载目录（桌面端，或 Android 选中的公共目录——
  /// 公共目录无需授权、直接按路径写入）；已有 SAF 目录授权会一并释放。
  Future<void> setDownloadDir(String? dir) async {
    await downloadDirectorySettings.selectDirectoryPath(dir);
  }

  /// 保存 SAF 授权目录（Android，见 [SafStorage.pickDirectory]）。
  /// 原始的路径设置在 SAF 模式下不再使用，旧目录授权同时释放。
  Future<void> setSafDownloadDir(SafDirectory dir) async {
    await downloadDirectorySettings.selectSafariDirectory(dir);
  }

  /// 系统是否要求「少动效」（移除动画 / 减弱动态效果 / 读屏接管）。
  /// 由外壳在 didChangeDependencies 里同步：控制器里拿不到 MediaQuery，
  /// 但顶栏/底栏的滑出这类装饰性动画要跟着系统设置走。
  bool get systemReduceMotion => runtimeState.systemReduceMotion.value;
  set systemReduceMotion(bool value) =>
      runtimeState.systemReduceMotion.value = value;

  /// 当前是否应该少动效：用户设置（全局动画）+ 系统信号合成后的结论。
  /// 控制器内的动画用它判断；widget 侧统一用 reduceMotionOf()。
  bool get motionReduced {
    switch (settings.motionMode) {
      case 'on':
        return false;
      case 'off':
        return true;
    }
    return systemReduceMotion ||
        SystemMotion.reduceMotion.value ||
        SystemMotion.touchExploration.value;
  }

  /// 顶栏/底栏滑动隐藏进度 0..1，由各页面按滚动距离驱动。
  ValueNotifier<double> get barsHide => navigation.barsHide;

  /// 当前激活的 page 视图下标。
  ValueNotifier<int> get activeTab => navigation.activeTab;

  /// 顶栏收起进度 0..1。
  ValueNotifier<double> get topBarHide => navigation.topBarHide;

  /// 首页“目录打开方式 = 网盘页”时请求打开的目录 id（消费后置空）。
  ValueNotifier<String?> get driveFolderRequest => drive.folderRequest;

  /// 网盘页当前所在目录（拖拽上传的确认条要显示目标路径）。
  ValueNotifier<DriveLocation> get driveLocation => drive.location;

  /// 拖拽判定：当前是否"可见地"处于收藏页。收藏页有底栏 tab 与独立路由
  /// 两种形态，各自注册一个探针（被别的页面盖住时探针返回 false）。
  void addFavoritesProbe(bool Function() probe) =>
      drive.addFavoritesProbe(probe);

  void removeFavoritesProbe(bool Function() probe) =>
      drive.removeFavoritesProbe(probe);

  bool get favoritesVisible => drive.favoritesVisible;

  /// 拖拽判定：当前是否"可见地"处于网盘页（底栏 tab 或独立路由）。
  void addDriveProbe(bool Function() probe) => drive.addDriveProbe(probe);

  void removeDriveProbe(bool Function() probe) => drive.removeDriveProbe(probe);

  bool get driveVisible => drive.driveVisible;

  /// 由外壳注册：切换到指定 page 视图。
  void Function(int index)? get onSwitchTab => navigation.onSwitchTab;
  set onSwitchTab(void Function(int index)? handler) =>
      navigation.onSwitchTab = handler;

  void switchTab(int index) => navigation.switchTab(index);

  /// 在网盘页打开指定目录，并切换到网盘视图。
  void openFolderInDrive(String folderId) {
    driveFolderRequest.value = folderId;
    switchTab(1);
  }

  /// 滚动驱动：1:1 跟随手指，立即生效并打断正在播放的程序化动画。
  void setBarsHideFromScroll(double value) =>
      navigation.setBarsHideFromScroll(value);

  /// 顶栏滚动驱动：1:1 跟随手指（距离由各页面的顶栏高度决定）。
  void setTopBarHideFromScroll(double value) =>
      navigation.setTopBarHideFromScroll(value);

  /// 程序化显示/隐藏：平滑过渡。
  /// 例如加载新目录时把已收起的顶/底栏调出来，会滑动出现而不是瞬间弹出。
  void animateBarsHide(
    double target, {
    Duration duration = const Duration(milliseconds: 240),
    Curve curve = Curves.easeOutCubic,
  }) => navigation.animateBarsHide(
    target,
    reduceMotion: motionReduced,
    duration: duration,
    curve: curve,
  );

  @override
  void dispose() {
    accountState.removeListener(notifyListeners);
    navigation.removeListener(notifyListeners);
    navigationAppearanceSettings.revision.removeListener(notifyListeners);
    themeSettings.revision.removeListener(notifyListeners);
    languageClipboardSettings.revision.removeListener(notifyListeners);
    listHomeSettings.revision.removeListener(notifyListeners);
    downloadDirectorySettings.revision.removeListener(notifyListeners);
    accountState.dispose();
    navigation.dispose();
    drive.dispose();
    runtimeState.dispose();
    super.dispose();
  }

  Future<void> setHideTopBar(bool value) async {
    await navigationAppearanceSettings.setHideTopBar(value);
  }

  Future<void> setHideBottomBar(bool value) async {
    await navigationAppearanceSettings.setHideBottomBar(value);
  }

  Future<void> setFloatingNavBar(bool value) async {
    await navigationAppearanceSettings.setFloatingNavBar(value);
  }

  Future<void> setTransitionAnimations(bool value) async {
    await navigationAppearanceSettings.setTransitionAnimations(value);
  }

  Future<void> setNotifyProgress(bool value) async {
    await notificationSettings.setNotifyProgress(value);
    notifyListeners();
  }

  Future<void> setNotifyDone(bool value) async {
    await notificationSettings.setNotifyDone(value);
    notifyListeners();
  }

  Future<void> setSortMode(String value) async {
    await listHomeSettings.setSortMode(value);
  }

  Future<void> setQuickExpanded(bool value) async {
    await listHomeSettings.setQuickExpanded(value);
  }

  Future<void> setRecentsExpanded(bool value) async {
    await listHomeSettings.setRecentsExpanded(value);
  }

  /// 设置最近使用条数（0 = 不记录），并立刻按新上限裁剪已有记录。
  Future<void> setRecentLimit(int value) async {
    await listHomeSettings.setRecentLimit(value);
  }

  Future<void> setMaxUploads(int value) async {
    await transferConnectionSettings.setMaxUploads(value);
    notifyListeners();
  }

  Future<void> setMaxDownloads(int value) async {
    await transferConnectionSettings.setMaxDownloads(value);
    notifyListeners();
  }

  String? get activeUid => accounts.activeUid;

  Account? get activeAccount => accounts.active;

  LanzouClient? get client {
    final uid = activeUid;
    return uid == null ? null : clientFor(uid);
  }

  LanzouClient clientFor(String uid) => clientRegistry.clientFor(
    uid,
    cookie: accounts.byUid(uid)?.cookie,
  );

  /// 用于解析公开分享链接（不依赖登录态）。
  LanzouClient get publicClient => clientRegistry.publicClient;

  Future<void> addAccountFromCookie(String rawCookie) async {
    await accountLogin.addAccountFromCookie(rawCookie);
  }

  /// 账号缺昵称 / 等级时，后台解析一次网页版个人中心并落盘。
  ///
  /// 等级没取到（页面结构变了等）不写空值，下次启动再试；界面同时会按
  /// 普通用户「普」显示（见 Account.levelLabel）。
  Future<void> _refreshActiveAccountInfo() async {
    final uid = accounts.activeUid;
    if (uid == null) return;
    final account = accounts.byUid(uid);
    if (account == null ||
        (account.nickname.isNotEmpty && account.level.isNotEmpty)) {
      return;
    }
    try {
      final info = await clientFor(uid).fetchAccountInfo();
      var changed = false;
      final nickname = info.nickname ?? '';
      if (nickname.isNotEmpty) {
        await accounts.setNickname(uid, nickname);
        changed = true;
      }
      if (info.level.isNotEmpty) {
        await accounts.setLevel(uid, info.level);
        changed = true;
      }
      if (changed) accountState.notifyAccountChanged();
    } catch (_) {}
  }

  Future<void> switchAccount(String uid) async {
    await accountSession.switchAccount(uid);
  }

  /// 移除账号。[clearData] 为 true 时一并清掉本机里这个账号的使用数据
  /// （快速访问、最近使用）。
  Future<void> removeAccount(String uid, {bool clearData = false}) async {
    await accountSession.removeAccount(uid, clearData: clearData);
  }

  Future<void> setGridView(bool value) async {
    await cachePageSettings.setGridView(value);
    notifyListeners();
  }

  Future<void> setLaunchPage(String page) async {
    await cachePageSettings.setLaunchPage(page);
    notifyListeners();
  }

  Future<void> setHomeFolderOpenMode(String value) async {
    await listHomeSettings.setHomeFolderOpenMode(value);
  }

  Future<void> setCacheFolders(bool value) async {
    await cachePageSettings.setCacheFolders(value);
    notifyListeners();
  }

  Future<void> setLoadAllPages(bool value) async {
    await cachePageSettings.setLoadAllPages(value);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    await themeSettings.setThemeMode(mode);
  }

  /// 设置页「全局动画」：auto / on / off（见 [SystemMotion.motionMode]）。
  Future<void> setMotionMode(String mode) async {
    await themeSettings.setMotionMode(mode);
  }

  Future<void> setOledBlack(bool value) async {
    await themeSettings.setOledBlack(value);
  }

  /// 动态取色（跟随系统壁纸，Android 12+）。
  Future<void> setDynamicColor(bool value) async {
    await themeSettings.setDynamicColor(value);
  }

  /// 复制到蓝奏云分享链接时是否提示打开。
  Future<void> setClipboardLinkPrompt(bool value) async {
    await languageClipboardSettings.setClipboardLinkPrompt(value);
  }

  /// 「传输」「收藏」是否显示在底栏。
  Future<void> setNavShowTransfers(bool value) async {
    await navigationAppearanceSettings.setNavShowTransfers(value);
    notifyListeners();
  }

  Future<void> setNavShowFavorites(bool value) async {
    await navigationAppearanceSettings.setNavShowFavorites(value);
    notifyListeners();
  }

  Future<void> setThemeSeed(int value) async {
    await themeSettings.setThemeSeed(value);
  }

  Future<void> setLanguage(String value) async {
    await languageClipboardSettings.setLanguage(value);
  }
}
