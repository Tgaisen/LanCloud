import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _keyDownloadDir = 'download_dir';
  static const _keyGridView = 'grid_view';
  static const _keyLaunchPage = 'launch_page';
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
  static const _keySwipeTabs = 'swipe_tabs';
  static const _keyHideBars = 'hide_bars_on_scroll';
  static const _keyHideBarsMode = 'hide_bars_mode';
  static const _keyInstantHide = 'instant_hide';
  static const _keyFloatingNav = 'floating_nav_bar';

  String? downloadDir;
  bool gridView = true;
  String launchPage = 'home';
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
  bool swipeTabs = false;
  bool hideTopBar = false;
  bool hideBottomBar = false;
  /// 收起类型：false=同步（跟随滚动），true=即时（到阈值整块收起）
  bool instantHide = false;
  bool floatingNavBar = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    downloadDir = prefs.getString(_keyDownloadDir);
    gridView = prefs.getBool(_keyGridView) ?? true;
    launchPage = prefs.getString(_keyLaunchPage) ?? 'home';
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
    instantHide = prefs.getBool(_keyInstantHide) ?? false;
    floatingNavBar = prefs.getBool(_keyFloatingNav) ?? false;
  }

  Future<void> setHideTopBar(bool value) async {
    hideTopBar = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHideBars, value);
  }

  Future<void> setHideBottomBar(bool value) async {
    hideBottomBar = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHideBars, value);
  }

  Future<void> setInstantHide(bool value) async {
    instantHide = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInstantHide, value);
  }

  Future<void> setFloatingNavBar(bool value) async {
    floatingNavBar = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFloatingNav, value);
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

  Future<void> setGridView(bool value) async {
    gridView = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGridView, value);
  }
}
