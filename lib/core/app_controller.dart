import 'dart:async';
import 'dart:io';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api/lanzou_client.dart';
import 'data/account_store.dart';
import 'data/app_db.dart';
import 'data/settings_store.dart';
import 'drive_cache.dart';
import 'dynamic_color_support.dart';
import 'platform_support.dart';
import 'system_motion.dart';

/// 网盘页当前所在目录：id + 相对根目录的路径（不含"根目录"这几个字，
/// 显示时按当前语言拼）。拖拽上传的确认条用它显示目标位置。
class DriveLocation {
  const DriveLocation({this.id = '-1', this.path = ''});

  final String id;

  /// 例如 'abc/def'；根目录时为空串。
  final String path;

  @override
  bool operator ==(Object other) =>
      other is DriveLocation && other.id == id && other.path == path;

  @override
  int get hashCode => Object.hash(id, path);
}

class AppController extends ChangeNotifier {
  final AccountStore accounts = AccountStore();
  final SettingsStore settings = SettingsStore();
  final AppDb db = AppDb.instance;
  final DriveCache driveCache = DriveCache();
  final Map<String, LanzouClient> _clients = {};
  LanzouClient? _publicClient;

  bool ready = false;
  bool selectionMode = false;
  VoidCallback? onRequestExitSelection;

  /// 网盘页注册的返回处理：返回 true 表示已消费（例如返回上一级目录）。
  Future<bool> Function()? onDriveBack;

  /// 网盘页当前是否需要自己消费返回手势（多选 / 搜索 / 已在子目录），
  /// 由外壳里的 [DrivePage] 实时上报。RootShell 用它决定返回手势交给系统
  /// （系统才会播放退回桌面的预测性返回动画）还是由 Flutter 拦截。
  final ValueNotifier<bool> driveCanHandleBack = ValueNotifier<bool>(false);

  void setSelectionMode(bool value) {
    if (selectionMode == value) return;
    selectionMode = value;
    notifyListeners();
  }

  Future<void> init() async {
    await accounts.load();
    await settings.load();
    _applyRuntimeSettings();
    await driveCache.bindAccount(accounts.activeUid);
    ready = true;
    notifyListeners();
    _refreshActiveNickname();
    // 设备支持动态取色且用户还没选过：默认开启（之后尊重用户选择）
    unawaited(autoEnableDynamicColorIfSupported());
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
    LanzouClient.apiBase = _apiBaseFor(settings.apiHost);
    LanzouClient.userAgent = settings.userAgent;
    LanzouClient.uploadBase = _apiBaseFor(settings.apiHost);
    LanzouClient.uploadPath = settings.uploadPath;
  }

  /// 网盘接口域名（pc / up）。
  String _apiBaseFor(String host) =>
      host == 'up' ? 'https://up.woozooo.com' : 'https://pc.woozooo.com';

  /// 备份恢复后重新读取账号与设置，并重建网盘客户端。
  Future<void> reloadFromStorage() async {
    await accounts.load();
    await settings.load();
    _applyRuntimeSettings();
    _clients.clear();
    await driveCache.bindAccount(accounts.activeUid);
    if (!settings.cacheFolders) driveCache.clear();
    notifyListeners();
    _refreshActiveNickname();
  }

  Future<void> setRequestInterval(int ms) async {
    await settings.setRequestInterval(ms);
    LanzouClient.requestInterval = Duration(milliseconds: ms);
    notifyListeners();
  }

  Future<void> setApiHost(String host) async {
    await settings.setApiHost(host);
    // 上传接口域名跟随网盘接口域名，改这里要一起更新
    LanzouClient.apiBase = _apiBaseFor(host);
    LanzouClient.uploadBase = _apiBaseFor(host);
    notifyListeners();
  }

  Future<void> setUserAgent(String value) async {
    await settings.setUserAgent(value);
    LanzouClient.userAgent = value;
    notifyListeners();
  }

  Future<void> setUploadPath(String value) async {
    await settings.setUploadPath(value);
    LanzouClient.uploadPath = settings.uploadPath;
    notifyListeners();
  }

  Future<void> setSwipeTabs(bool value) async {
    await settings.setSwipeTabs(value);
    notifyListeners();
  }

  Future<void> setDownloadDir(String? dir) async {
    await settings.setDownloadDir(dir);
    notifyListeners();
  }

  /// 顶栏/底栏滑动隐藏进度 0..1，由各页面的 ScrollTint 按滚动距离驱动。
  final ValueNotifier<double> barsHide = ValueNotifier(0);

  /// 系统是否要求「少动效」（移除动画 / 减弱动态效果 / 读屏接管）。
  /// 由外壳在 didChangeDependencies 里同步：控制器里拿不到 MediaQuery，
  /// 但顶栏/底栏的滑出这类装饰性动画要跟着系统设置走。
  bool systemReduceMotion = false;

  /// 当前激活的 page 视图下标：页面据此把折叠的顶栏动画调出来。
  final ValueNotifier<int> activeTab = ValueNotifier(0);

  /// 顶栏收起进度 0..1：与底栏同一套手感，但收起距离等于顶栏自身高度，
  /// 因此滑动时两者都与手指 1:1 跟随。
  final ValueNotifier<double> topBarHide = ValueNotifier(0);

  /// 首页“目录打开方式 = 网盘页”时请求打开的目录 id（消费后置空）。
  final ValueNotifier<String?> driveFolderRequest = ValueNotifier(null);

  /// 网盘页当前所在目录（拖拽上传的确认条要显示目标路径）。
  final ValueNotifier<DriveLocation> driveLocation = ValueNotifier(
    const DriveLocation(),
  );

  /// 拖拽判定：当前是否"可见地"处于收藏页。收藏页有底栏 tab 与独立路由
  /// 两种形态，各自注册一个探针（被别的页面盖住时探针返回 false）。
  final List<bool Function()> _favoritesProbes = [];

  void addFavoritesProbe(bool Function() probe) => _favoritesProbes.add(probe);

  void removeFavoritesProbe(bool Function() probe) =>
      _favoritesProbes.remove(probe);

  bool get favoritesVisible => _favoritesProbes.any((probe) {
    try {
      return probe();
    } catch (_) {
      return false;
    }
  });

  /// 拖拽判定：当前是否"可见地"处于网盘页（底栏 tab 或独立路由）。
  final List<bool Function()> _driveProbes = [];

  void addDriveProbe(bool Function() probe) => _driveProbes.add(probe);

  void removeDriveProbe(bool Function() probe) => _driveProbes.remove(probe);

  bool get driveVisible => _driveProbes.any((probe) {
    try {
      return probe();
    } catch (_) {
      return false;
    }
  });

  /// 由外壳注册：切换到指定 page 视图。
  void Function(int index)? onSwitchTab;

  void switchTab(int index) => onSwitchTab?.call(index);

  /// 在网盘页打开指定目录，并切换到网盘视图。
  void openFolderInDrive(String folderId) {
    driveFolderRequest.value = folderId;
    switchTab(1);
  }

  late final Ticker _barsTicker = Ticker(_onBarsTick);
  double _barsFrom = 0;
  double _barsTo = 0;
  double _topBarFrom = 0;
  Curve _barsCurve = Curves.easeOutCubic;
  Duration _barsDuration = const Duration(milliseconds: 240);

  /// 滚动驱动：1:1 跟随手指，立即生效并打断正在播放的程序化动画。
  void setBarsHideFromScroll(double value) {
    if (_barsTicker.isActive) _barsTicker.stop();
    final target = value.clamp(0.0, 1.0);
    if (barsHide.value != target) barsHide.value = target;
  }

  /// 顶栏滚动驱动：1:1 跟随手指（距离由各页面的顶栏高度决定）。
  void setTopBarHideFromScroll(double value) {
    if (_barsTicker.isActive) _barsTicker.stop();
    final target = value.clamp(0.0, 1.0);
    if (topBarHide.value != target) topBarHide.value = target;
  }

  /// 程序化显示/隐藏：平滑过渡。
  /// 例如加载新目录时把已收起的顶/底栏调出来，会滑动出现而不是瞬间弹出。
  void animateBarsHide(
    double target, {
    Duration duration = const Duration(milliseconds: 240),
    Curve curve = Curves.easeOutCubic,
  }) {
    final to = target.clamp(0.0, 1.0);
    // 系统要求少动效：顶栏/底栏直接到位，不做下滑
    // （systemReduceMotion 由外壳从 MediaQuery 同步，SystemMotion 是原生读到的
    //   动画缩放，覆盖华为等引擎看不到的 ROM）
    if (systemReduceMotion || SystemMotion.reduceMotion.value) {
      _barsTicker.stop();
      if (barsHide.value != to) barsHide.value = to;
      if (topBarHide.value != to) topBarHide.value = to;
      return;
    }
    if (to == barsHide.value && to == topBarHide.value) return;
    _barsFrom = barsHide.value;
    _topBarFrom = topBarHide.value;
    _barsTo = to;
    _barsCurve = curve;
    _barsDuration = duration;
    _barsTicker
      ..stop()
      ..start();
  }

  void _onBarsTick(Duration elapsed) {
    final total = _barsDuration.inMicroseconds;
    final t = total <= 0
        ? 1.0
        : (elapsed.inMicroseconds / total).clamp(0.0, 1.0);
    barsHide.value =
        (_barsFrom + (_barsTo - _barsFrom) * _barsCurve.transform(t)).clamp(
          0.0,
          1.0,
        );
    topBarHide.value =
        (_topBarFrom + (_barsTo - _topBarFrom) * _barsCurve.transform(t)).clamp(
          0.0,
          1.0,
        );
    if (t >= 1) _barsTicker.stop();
  }

  @override
  void dispose() {
    _barsTicker.dispose();
    barsHide.dispose();
    topBarHide.dispose();
    activeTab.dispose();
    driveFolderRequest.dispose();
    driveLocation.dispose();
    super.dispose();
  }

  Future<void> setHideTopBar(bool value) async {
    await settings.setHideTopBar(value);
    if (!value) animateBarsHide(0);
    notifyListeners();
  }

  Future<void> setHideBottomBar(bool value) async {
    await settings.setHideBottomBar(value);
    if (!value) animateBarsHide(0);
    notifyListeners();
  }

  Future<void> setFloatingNavBar(bool value) async {
    await settings.setFloatingNavBar(value);
    notifyListeners();
  }

  Future<void> setTransitionAnimations(bool value) async {
    await settings.setTransitionAnimations(value);
    notifyListeners();
  }

  Future<void> setNotifyProgress(bool value) async {
    await settings.setNotifyProgress(value);
    notifyListeners();
  }

  Future<void> setNotifyDone(bool value) async {
    await settings.setNotifyDone(value);
    notifyListeners();
  }

  Future<void> setSortMode(String value) async {
    await settings.setSortMode(value);
    notifyListeners();
  }

  Future<void> setQuickExpanded(bool value) async {
    await settings.setQuickExpanded(value);
    notifyListeners();
  }

  Future<void> setRecentsExpanded(bool value) async {
    await settings.setRecentsExpanded(value);
    notifyListeners();
  }

  /// 设置最近使用条数（0 = 不记录），并立刻按新上限裁剪已有记录。
  Future<void> setRecentLimit(int value) async {
    await settings.setRecentLimit(value);
    final uid = activeUid;
    if (uid != null) await db.trimRecents(uid, value);
    notifyListeners();
  }

  Future<void> setMaxUploads(int value) async {
    await settings.setMaxUploads(value);
    notifyListeners();
  }

  Future<void> setMaxDownloads(int value) async {
    await settings.setMaxDownloads(value);
    notifyListeners();
  }

  String? get activeUid => accounts.activeUid;

  Account? get activeAccount => accounts.active;

  LanzouClient? get client {
    final uid = activeUid;
    return uid == null ? null : clientFor(uid);
  }

  LanzouClient clientFor(String uid) => _clients.putIfAbsent(uid, () {
    final account = accounts.byUid(uid);
    final c = LanzouClient(uid: uid);
    if (account != null) c.setCookieHeader(account.cookie);
    return c;
  });

  /// 用于解析公开分享链接（不依赖登录态）。
  LanzouClient get publicClient => _publicClient ??= LanzouClient(uid: '0');

  Future<void> addAccountFromCookie(String rawCookie) async {
    final cookie = rawCookie.trim();
    final uid = RegExp(r'ylogin=(\d+)').firstMatch(cookie)?.group(1);
    if (uid == null) {
      throw const CookieFormatException();
    }
    final c = LanzouClient(uid: uid)..setCookieHeader(cookie);
    final ok = await c.verify();
    if (!ok) throw const CookieInvalidException();
    var nickname = '';
    try {
      nickname = await c.fetchNickname() ?? '';
    } catch (_) {}
    await accounts.upsert(
      Account(uid: uid, cookie: cookie, nickname: nickname),
    );
    _clients[uid] = c;
    // 新账号登入后同样清掉上一个账号的网盘缓存
    await driveCache.bindAccount(accounts.activeUid);
    notifyListeners();
  }

  /// 账号没有昵称时，后台解析一次网页版个人中心并落盘。
  Future<void> _refreshActiveNickname() async {
    final uid = accounts.activeUid;
    if (uid == null) return;
    final account = accounts.byUid(uid);
    if (account == null || account.nickname.isNotEmpty) return;
    try {
      final nickname = await clientFor(uid).fetchNickname();
      if (nickname == null || nickname.isEmpty) return;
      await accounts.setNickname(uid, nickname);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> switchAccount(String uid) async {
    await accounts.setActive(uid);
    // 网盘缓存按账号隔离：换账号时清掉旧账号的目录缓存
    await driveCache.bindAccount(uid);
    notifyListeners();
  }

  Future<void> removeAccount(String uid) async {
    await accounts.remove(uid);
    _clients.remove(uid);
    await driveCache.bindAccount(accounts.activeUid);
    notifyListeners();
  }

  /// 默认下载目录路径。
  ///
  /// Android：Android/data/<包名>/files/LanCloud（取不到外部专属目录时
  /// 退回应用私有文档目录）；桌面端：系统「下载」目录下的 LanCloud
  /// （取不到时退回应用文档目录）。
  Future<String> defaultDownloadDirPath() async {
    final Directory base;
    if (PlatformSupport.isMobile) {
      base =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    return p.join(base.path, 'LanCloud');
  }

  Future<Directory> downloadDirectory() async {
    Directory dir;
    final custom = settings.downloadDir;
    if (custom != null && custom.isNotEmpty) {
      dir = Directory(custom);
    } else {
      dir = Directory(await defaultDownloadDirPath());
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> setGridView(bool value) async {
    await settings.setGridView(value);
    notifyListeners();
  }

  Future<void> setLaunchPage(String page) async {
    await settings.setLaunchPage(page);
    notifyListeners();
  }

  Future<void> setHomeFolderOpenMode(String value) async {
    await settings.setHomeFolderOpenMode(value);
    notifyListeners();
  }

  Future<void> setCacheFolders(bool value) async {
    await settings.setCacheFolders(value);
    if (!value) driveCache.clear();
    notifyListeners();
  }

  Future<void> setLoadAllPages(bool value) async {
    await settings.setLoadAllPages(value);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    await settings.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setOledBlack(bool value) async {
    await settings.setOledBlack(value);
    notifyListeners();
  }

  /// 动态取色（跟随系统壁纸，Android 12+）。
  Future<void> setDynamicColor(bool value) async {
    await settings.setDynamicColor(value);
    notifyListeners();
  }

  /// 复制到蓝奏云分享链接时是否提示打开。
  Future<void> setClipboardLinkPrompt(bool value) async {
    await settings.setClipboardLinkPrompt(value);
    notifyListeners();
  }

  /// 「传输」「收藏」是否显示在底栏。
  Future<void> setNavShowTransfers(bool value) async {
    await settings.setNavShowTransfers(value);
    notifyListeners();
  }

  Future<void> setNavShowFavorites(bool value) async {
    await settings.setNavShowFavorites(value);
    notifyListeners();
  }

  Future<void> setThemeSeed(int value) async {
    await settings.setThemeSeed(value);
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    await settings.setLanguage(value);
    notifyListeners();
  }

  Future<String> uniqueSavePath(String name) async {
    final dir = await downloadDirectory();
    var path = p.join(dir.path, name);
    var i = 1;
    final ext = p.extension(name);
    final baseName = p.basenameWithoutExtension(name);
    while (await File(path).exists()) {
      path = p.join(dir.path, '$baseName($i)$ext');
      i += 1;
    }
    return path;
  }
}
