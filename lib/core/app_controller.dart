import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/lanzou_client.dart';
import 'api/lanzou_client_registry.dart';
import 'account_state.dart';
import 'account_login.dart';
import 'account_session.dart';
import 'app_log.dart';
import 'app_runtime_state.dart';
import 'data/app_db.dart';
import 'data/secure_storage.dart';
import 'download_directory_settings_state.dart';
import 'drive_state.dart';
import 'cache_page_settings_state.dart';
import 'navigation_state.dart';
import 'navigation_appearance_settings_state.dart';
import 'notification_settings_state.dart';
import 'list_home_settings_state.dart';
import 'language_clipboard_settings_state.dart';
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
    final accountStore = this.accountState.store;
    final settingsStore = this.settingsState.store;
    updateSettings = UpdateSettingsState(settingsStore);
    notificationSettings = NotificationSettingsState(settingsStore);
    navigationAppearanceSettings = NavigationAppearanceSettingsState(
      settingsStore,
      navigation: this.navigation,
      reduceMotion: () => _motionReduced,
    );
    themeSettings = ThemeSettingsState(settingsStore);
    transferConnectionSettings = TransferConnectionSettingsState(
      settingsStore,
    );
    listHomeSettings = ListHomeSettingsState(
      settingsStore,
      trimRecents: db.trimRecents,
      activeUid: () => accountStore.activeUid,
    );
    languageClipboardSettings = LanguageClipboardSettingsState(settingsStore);
    cachePageSettings = CachePageSettingsState(
      settingsStore,
      this.drive.cache,
    );
    downloadDirectorySettings = DownloadDirectorySettingsState(settingsStore);
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

  final AppDb db = AppDb.instance;
  final NavigationState navigation;
  final DriveState drive;

  final LanzouClientRegistry clientRegistry = LanzouClientRegistry();
  late final AccountLogin accountLogin = AccountLogin(
    accountState: accountState,
    clients: clientRegistry,
    driveCache: drive.cache,
  );
  late final AccountSession accountSession = AccountSession(
    accountState: accountState,
    clients: clientRegistry,
    driveCache: drive.cache,
    db: db,
  );

  Future<void> init() async {
    await _inspectSecureStorageUpgrade();
    final accountStore = accountState.store;
    final settingsStore = settingsState.store;
    await accountStore.load();
    await settingsStore.load();
    _applyRuntimeSettings();
    await drive.cache.bindAccount(accountStore.activeUid);
    runtimeState.ready.value = true;
    notifyListeners();
    _refreshActiveAccountInfo();
    // 设备支持动态取色且用户还没选过：默认开启（之后尊重用户选择）
    unawaited(themeSettings.enableDynamicColorIfUnset());
  }

  /// v11 会移除旧密文和旧加密后端的读取能力。必须在账号存储第一次读取前
  /// 检查；不可迁移时账号存储会回到空状态，外壳随后稳定落到登录页。
  Future<void> _inspectSecureStorageUpgrade() async {
    try {
      final status = await checkSecureStorageUpgradeOnce();
      if (status == null) return;
      runtimeState.secureStorageNeedsReauthentication.value =
          status.hasDataLoss || status.willDiscardOnNextAccess;
      if (runtimeState.secureStorageNeedsReauthentication.value) {
        AppLog.instance.log('secure_storage', '需要重新登录：$status');
      }
    } catch (error, stack) {
      // 状态检查失败不阻断启动；真正的读取仍有插件自身兜底。
      AppLog.instance.error('secure_storage', error, stack);
    }
  }

  void _applyRuntimeSettings() {
    final settingsStore = settingsState.store;
    LanzouClient.requestInterval = Duration(
      milliseconds: settingsStore.requestInterval,
    );
    LanzouClient.apiBase = lanzouApiBaseForHost(settingsStore.apiHost);
    LanzouClient.userAgent = settingsStore.userAgent;
    LanzouClient.uploadPath = settingsStore.uploadPath;
    // 设置页「全局动画」：同步给 SystemMotion，根 widget 监听它整树重建，
    // 各处 reduceMotionOf() 立刻按新值生效（备份恢复走同一入口）。
    SystemMotion.motionMode.value = settingsStore.motionMode;
  }

  /// 备份恢复后重新读取账号与设置，并重建网盘客户端。
  Future<void> reloadFromStorage() async {
    final accountStore = accountState.store;
    final settingsStore = settingsState.store;
    await accountStore.load();
    if (accountStore.accounts.isNotEmpty) {
      runtimeState.secureStorageNeedsReauthentication.value = false;
    }
    await settingsStore.load();
    _applyRuntimeSettings();
    themeSettings.refresh();
    languageClipboardSettings.refresh();
    clientRegistry.clearAccounts();
    await drive.cache.bindAccount(accountStore.activeUid);
    if (!settingsStore.cacheFolders) drive.cache.clear();
    notifyListeners();
    _refreshActiveAccountInfo();
  }

  /// 当前是否应该少动效：用户设置（全局动画）+ 系统信号合成后的结论。
  /// 控制器内的动画用它判断；widget 侧统一用 reduceMotionOf()。
  bool get _motionReduced {
    switch (settingsState.store.motionMode) {
      case 'on':
        return false;
      case 'off':
        return true;
    }
    return runtimeState.systemReduceMotion.value ||
        SystemMotion.reduceMotion.value ||
        SystemMotion.touchExploration.value;
  }

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

  /// 账号缺昵称 / 等级时，后台解析一次网页版个人中心并落盘。
  ///
  /// 等级没取到（页面结构变了等）不写空值，下次启动再试；界面同时会按
  /// 普通用户「普」显示（见 Account.levelLabel）。
  Future<void> _refreshActiveAccountInfo() async {
    final accountStore = accountState.store;
    final uid = accountStore.activeUid;
    if (uid == null) return;
    final account = accountStore.byUid(uid);
    if (account == null ||
        (account.nickname.isNotEmpty && account.level.isNotEmpty)) {
      return;
    }
    try {
      final info = await clientRegistry
          .clientFor(uid, cookie: accountStore.byUid(uid)?.cookie)
          .fetchAccountInfo();
      var changed = false;
      final nickname = info.nickname ?? '';
      if (nickname.isNotEmpty) {
        await accountStore.setNickname(uid, nickname);
        changed = true;
      }
      if (info.level.isNotEmpty) {
        await accountStore.setLevel(uid, info.level);
        changed = true;
      }
      if (changed) accountState.notifyAccountChanged();
    } catch (_) {}
  }

}
