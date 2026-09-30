import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api/lanzou_client.dart';
import 'data/account_store.dart';
import 'data/app_db.dart';
import 'data/settings_store.dart';
import 'drive_cache.dart';

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

  void setSelectionMode(bool value) {
    if (selectionMode == value) return;
    selectionMode = value;
    notifyListeners();
  }

  Future<void> init() async {
    await accounts.load();
    await settings.load();
    LanzouClient.requestInterval =
        Duration(milliseconds: settings.requestInterval);
    LanzouClient.apiBase = settings.apiHost == 'up'
        ? 'https://up.woozooo.com'
        : 'https://pc.woozooo.com';
    LanzouClient.userAgent = settings.userAgent;
    ready = true;
    notifyListeners();
  }

  Future<void> setRequestInterval(int ms) async {
    await settings.setRequestInterval(ms);
    LanzouClient.requestInterval = Duration(milliseconds: ms);
    notifyListeners();
  }

  Future<void> setApiHost(String host) async {
    await settings.setApiHost(host);
    LanzouClient.apiBase = host == 'up'
        ? 'https://up.woozooo.com'
        : 'https://pc.woozooo.com';
    notifyListeners();
  }

  Future<void> setUserAgent(String value) async {
    await settings.setUserAgent(value);
    LanzouClient.userAgent = value;
    notifyListeners();
  }

  Future<void> setSwipeTabs(bool value) async {
    await settings.setSwipeTabs(value);
    notifyListeners();
  }

  bool barsHidden = false;

  void setBarsHidden(bool value) {
    if (barsHidden == value) return;
    barsHidden = value;
    notifyListeners();
  }

  Future<void> setHideTopBar(bool value) async {
    await settings.setHideTopBar(value);
    if (!value) setBarsHidden(false);
    notifyListeners();
  }

  Future<void> setHideBottomBar(bool value) async {
    await settings.setHideBottomBar(value);
    notifyListeners();
  }

  Future<void> setInstantHide(bool value) async {
    await settings.setInstantHide(value);
    notifyListeners();
  }

  Future<void> setFloatingNavBar(bool value) async {
    await settings.setFloatingNavBar(value);
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
      throw const LanzouException('未找到 ylogin，请确认复制的是完整 Cookie');
    }
    final c = LanzouClient(uid: uid)..setCookieHeader(cookie);
    final ok = await c.verify();
    if (!ok) throw const LanzouException('Cookie 无效或已过期，请重新获取');
    await accounts.upsert(Account(uid: uid, cookie: cookie, nickname: '账号 $uid'));
    _clients[uid] = c;
    notifyListeners();
  }

  Future<void> switchAccount(String uid) async {
    await accounts.setActive(uid);
    notifyListeners();
  }

  Future<void> removeAccount(String uid) async {
    await accounts.remove(uid);
    _clients.remove(uid);
    notifyListeners();
  }

  Future<Directory> downloadDirectory() async {
    Directory dir;
    final custom = settings.downloadDir;
    if (custom != null && custom.isNotEmpty) {
      dir = Directory(custom);
    } else {
      final base = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(base.path, 'LanCloud'));
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

  Future<void> setThemeSeed(int value) async {
    await settings.setThemeSeed(value);
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
