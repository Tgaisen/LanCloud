import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _keyLanguage = 'language';
  static const _keyDownloadDir = 'download_dir';
  static const _keyGridView = 'grid_view';
  static const _keyLaunchPage = 'launch_page';
  static const _keyHomeFolderOpen = 'home_folder_open';
  static const _keyCacheFolders = 'cache_folders';
  static const _keyLoadAllPages = 'load_all_pages';
  static const _keyThemeMode = 'theme_mode';
  static const _keyOled = 'oled_black';
  static const _keySeed = 'theme_seed';
  static const _keyInterval = 'request_interval';
  static const _keyMaxUp = 'max_uploads';
  static const _keyMaxDown = 'max_downloads';
  static const _keyApiHost = 'api_host';
  static const _keyUserAgent = 'user_agent';
  static const _keyUploadDomain = 'upload_domain';
  static const _keyShareDomain = 'share_domain';
  static const _keySwipeTabs = 'swipe_tabs';
  static const _keyHideBars = 'hide_bars_on_scroll';
  static const _keyHideBarsMode = 'hide_bars_mode';
  static const _keyHideTopBar = 'hide_top_bar';
  static const _keyHideBottomBar = 'hide_bottom_bar';
  static const _keyFloatingNav = 'floating_nav_bar';
  static const _keyTransitions = 'transition_animations';
  static const _keyNotifyProgress = 'notify_progress';
  static const _keyNotifyDone = 'notify_done';
  static const _keySortMode = 'sort_mode';

  String? downloadDir;
  String language = 'system';
  bool gridView = true;
  String launchPage = 'home';
  /// 首页目录打开方式：page = 新页面，drive = 跳转网盘页。
  String homeFolderOpenMode = 'page';
  bool cacheFolders = true;
  bool loadAllPages = false;
  String themeMode = 'system';
  bool oledBlack = false;
  int themeSeed = 0xFF2E6BE6;
  int requestInterval = 300;
  int maxUploads = 1;
  int maxDownloads = 3;
  String apiHost = 'pc';
  String userAgent = '';
  /// 自定义上传域名，留空使用默认 up.woozooo.com。
  String uploadDomain = '';
  /// 自定义分享链接域名，留空使用内置镜像回退列表。
  String shareDomain = '';
  bool swipeTabs = false;
  bool hideTopBar = false;
  bool hideBottomBar = false;
  bool floatingNavBar = false;
  /// 目录切换与列表出现动画，关闭可减少低端设备掉帧。
  bool transitionAnimations = true;
  /// 传输进行中在通知栏显示进度。
  bool notifyProgress = true;
  /// 下载或上传完成时提醒。
  bool notifyDone = true;
  /// 网盘文件排序方式：default / name / size / time。
  String sortMode = 'default';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString(_keyLanguage) ?? 'system';
    downloadDir = prefs.getString(_keyDownloadDir);
    gridView = prefs.getBool(_keyGridView) ?? true;
    launchPage = prefs.getString(_keyLaunchPage) ?? 'home';
    homeFolderOpenMode = prefs.getString(_keyHomeFolderOpen) ?? 'page';
    cacheFolders = prefs.getBool(_keyCacheFolders) ?? true;
    loadAllPages = prefs.getBool(_keyLoadAllPages) ?? false;
    themeMode = prefs.getString(_keyThemeMode) ?? 'system';
    oledBlack = prefs.getBool(_keyOled) ?? false;
    themeSeed = prefs.getInt(_keySeed) ?? 0xFF2E6BE6;
    requestInterval = prefs.getInt(_keyInterval) ?? 300;
    maxUploads = prefs.getInt(_keyMaxUp) ?? 1;
    maxDownloads = prefs.getInt(_keyMaxDown) ?? 3;
    apiHost = prefs.getString(_keyApiHost) ?? 'pc';
    userAgent = prefs.getString(_keyUserAgent) ?? '';
    uploadDomain = prefs.getString(_keyUploadDomain) ?? '';
    shareDomain = prefs.getString(_keyShareDomain) ?? '';
    swipeTabs = prefs.getBool(_keySwipeTabs) ?? false;
    final legacyMode = prefs.getString(_keyHideBarsMode);
    if (legacyMode != null) {
      hideTopBar = legacyMode == 'top' || legacyMode == 'both';
      hideBottomBar = legacyMode == 'bottom' || legacyMode == 'both';
    } else {
      final legacyBool = prefs.getBool(_keyHideBars) ?? false;
      hideTopBar = legacyBool;
      hideBottomBar = legacyBool;
    }
    hideTopBar = prefs.getBool(_keyHideTopBar) ?? hideTopBar;
    hideBottomBar = prefs.getBool(_keyHideBottomBar) ?? hideBottomBar;
    floatingNavBar = prefs.getBool(_keyFloatingNav) ?? false;
    transitionAnimations = prefs.getBool(_keyTransitions) ?? true;
    notifyProgress = prefs.getBool(_keyNotifyProgress) ?? true;
    notifyDone = prefs.getBool(_keyNotifyDone) ?? true;
    sortMode = prefs.getString(_keySortMode) ?? 'default';
  }

  Future<void> setNotifyProgress(bool value) async {
    notifyProgress = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifyProgress, value);
  }

  Future<void> setNotifyDone(bool value) async {
    notifyDone = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifyDone, value);
  }

  Future<void> setSortMode(String value) async {
    sortMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySortMode, value);
  }

  Future<void> setHideTopBar(bool value) async {
    hideTopBar = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHideTopBar, value);
  }

  Future<void> setHideBottomBar(bool value) async {
    hideBottomBar = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHideBottomBar, value);
  }

  Future<void> setFloatingNavBar(bool value) async {
    floatingNavBar = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFloatingNav, value);
  }

  Future<void> setTransitionAnimations(bool value) async {
    transitionAnimations = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTransitions, value);
  }

  Future<void> setSwipeTabs(bool value) async {
    swipeTabs = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySwipeTabs, value);
  }

  Future<void> setApiHost(String value) async {
    apiHost = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiHost, value);
  }

  Future<void> setUserAgent(String value) async {
    userAgent = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserAgent, value);
  }

  Future<void> setUploadDomain(String value) async {
    uploadDomain = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (uploadDomain.isEmpty) {
      await prefs.remove(_keyUploadDomain);
    } else {
      await prefs.setString(_keyUploadDomain, uploadDomain);
    }
  }

  Future<void> setShareDomain(String value) async {
    shareDomain = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (shareDomain.isEmpty) {
      await prefs.remove(_keyShareDomain);
    } else {
      await prefs.setString(_keyShareDomain, shareDomain);
    }
  }

  Future<void> setRequestInterval(int value) async {
    requestInterval = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInterval, value);
  }

  Future<void> setMaxUploads(int value) async {
    maxUploads = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxUp, value);
  }

  Future<void> setMaxDownloads(int value) async {
    maxDownloads = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxDown, value);
  }

  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode);
  }

  Future<void> setOledBlack(bool value) async {
    oledBlack = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOled, value);
  }

  Future<void> setThemeSeed(int value) async {
    themeSeed = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeed, value);
  }

  Future<void> setLaunchPage(String page) async {
    launchPage = page;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLaunchPage, page);
  }

  Future<void> setHomeFolderOpenMode(String value) async {
    homeFolderOpenMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHomeFolderOpen, value);
  }

  Future<void> setCacheFolders(bool value) async {
    cacheFolders = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCacheFolders, value);
  }

  Future<void> setLoadAllPages(bool value) async {
    loadAllPages = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLoadAllPages, value);
  }

  Future<void> setDownloadDir(String? dir) async {
    downloadDir = (dir == null || dir.isEmpty) ? null : dir;
    final prefs = await SharedPreferences.getInstance();
    if (downloadDir == null) {
      await prefs.remove(_keyDownloadDir);
    } else {
      await prefs.setString(_keyDownloadDir, downloadDir!);
    }
  }

  Future<void> setLanguage(String value) async {
    language = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, value);
  }

  Future<void> setGridView(bool value) async {
    gridView = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGridView, value);
  }
}
