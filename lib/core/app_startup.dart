import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api/lanzou_client.dart';
import 'app_environment.dart';
import 'app_log.dart';
import 'data/secure_storage.dart';
import 'system_motion.dart';
import 'transfer_connection_settings_state.dart';

/// 应用启动与恢复后的状态同步流程。
///
/// 本类只编排环境中的既有实例，不创建状态，也不接管平台服务初始化。
final class AppStartup {
  AppStartup({
    required this.environment,
    required this.onChanged,
    Future<SecureStorageUpgradeStatus?> Function()? secureStorageUpgradeCheck,
    Future<void> Function()? loadAccounts,
    Future<void> Function()? loadSettings,
    this.applyRuntimeSettings,
    Future<void> Function(String? uid)? bindDriveCache,
    this.refreshActiveAccountInfo,
    this.enableDynamicColorIfUnset,
  }) : _secureStorageUpgradeCheck =
           secureStorageUpgradeCheck ?? checkSecureStorageUpgradeOnce,
       _loadAccounts = loadAccounts ?? environment.accountState.store.load,
       _loadSettings = loadSettings ?? environment.settingsState.store.load,
       _bindDriveCache = bindDriveCache ?? environment.drive.cache.bindAccount;

  final AppEnvironment environment;
  final void Function() onChanged;
  final void Function()? applyRuntimeSettings;
  final Future<void> Function()? refreshActiveAccountInfo;
  final Future<void> Function()? enableDynamicColorIfUnset;
  final Future<SecureStorageUpgradeStatus?> Function()
  _secureStorageUpgradeCheck;
  final Future<void> Function() _loadAccounts;
  final Future<void> Function() _loadSettings;
  final Future<void> Function(String? uid) _bindDriveCache;

  Future<void> initialize() async {
    await _inspectSecureStorageUpgrade();
    final accountStore = environment.accountState.store;
    await _loadAccounts();
    await _loadSettings();
    _syncRuntimeSettings();
    await _bindDriveCache(accountStore.activeUid);
    environment.runtimeState.ready.value = true;
    onChanged();
    unawaited(_refreshActiveAccount());
    unawaited(_enableDynamicColor());
  }

  /// 备份恢复后重新读取账号与设置，并重建网盘客户端。
  Future<void> reloadFromStorage() async {
    final accountStore = environment.accountState.store;
    final settingsStore = environment.settingsState.store;
    await _loadAccounts();
    if (accountStore.accounts.isNotEmpty) {
      environment.runtimeState.secureStorageNeedsReauthentication.value = false;
    }
    await _loadSettings();
    _syncRuntimeSettings();
    environment.themeSettings.refresh();
    environment.languageClipboardSettings.refresh();
    environment.clientRegistry.clearAccounts();
    await _bindDriveCache(accountStore.activeUid);
    if (!settingsStore.cacheFolders) environment.drive.cache.clear();
    onChanged();
    unawaited(_refreshActiveAccount());
  }

  /// v11 会移除旧密文和旧加密后端的读取能力。必须在账号存储第一次读取前
  /// 检查；不可迁移时账号存储会回到空状态，外壳随后稳定落到登录页。
  Future<void> _inspectSecureStorageUpgrade() async {
    try {
      final status = await _secureStorageUpgradeCheck();
      if (status == null) return;
      environment.runtimeState.secureStorageNeedsReauthentication.value =
          status.hasDataLoss || status.willDiscardOnNextAccess;
      if (environment.runtimeState.secureStorageNeedsReauthentication.value) {
        AppLog.instance.log('secure_storage', '需要重新登录：$status');
      }
    } catch (error, stack) {
      // 状态检查失败不阻断启动；真正的读取仍有插件自身兜底。
      AppLog.instance.error('secure_storage', error, stack);
    }
  }

  void _syncRuntimeSettings() {
    final apply = applyRuntimeSettings;
    if (apply != null) {
      apply();
      return;
    }
    final settingsStore = environment.settingsState.store;
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

  Future<void> _enableDynamicColor() {
    return enableDynamicColorIfUnset?.call() ??
        environment.themeSettings.enableDynamicColorIfUnset();
  }

  Future<void> _refreshActiveAccount() {
    return refreshActiveAccountInfo?.call() ??
        _refreshActiveAccountInfoFromNetwork();
  }

  /// 账号缺昵称 / 等级时，后台解析一次网页版个人中心并落盘。
  ///
  /// 等级没取到（页面结构变了等）不写空值，下次启动再试；界面同时会按
  /// 普通用户「普」显示（见 `Account.levelLabel`）。
  Future<void> _refreshActiveAccountInfoFromNetwork() async {
    final accountStore = environment.accountState.store;
    final uid = accountStore.activeUid;
    if (uid == null) return;
    final account = accountStore.byUid(uid);
    if (account == null ||
        (account.nickname.isNotEmpty && account.level.isNotEmpty)) {
      return;
    }
    try {
      final info = await environment.clientRegistry
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
      if (changed) environment.accountState.notifyAccountChanged();
    } catch (_) {}
  }
}
