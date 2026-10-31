import 'account_login.dart';
import 'account_session.dart';
import 'account_state.dart';
import 'api/lanzou_client_registry.dart';
import 'app_runtime_state.dart';
import 'cache_page_settings_state.dart';
import 'data/app_db.dart';
import 'download_directory_settings_state.dart';
import 'drive_state.dart';
import 'language_clipboard_settings_state.dart';
import 'list_home_settings_state.dart';
import 'navigation_appearance_settings_state.dart';
import 'navigation_state.dart';
import 'notification_settings_state.dart';
import 'settings_state.dart';
import 'system_motion.dart';
import 'theme_settings_state.dart';
import 'transfer_connection_settings_state.dart';
import 'update/update_settings_state.dart';

/// 应用级状态与服务的唯一组装环境。
///
/// 本类只构造对象并保持实例同一性，不执行启动副作用；加载、运行时同步和
/// 生命周期通知仍由应用控制器的初始化流程负责。
final class AppEnvironment {
  AppEnvironment({
    AppDb? db,
    NavigationState? navigation,
    DriveState? drive,
    AccountState? accountState,
    SettingsState? settingsState,
    AppRuntimeState? runtimeState,
    LanzouClientRegistry? clientRegistry,
  }) : db = db ?? AppDb.instance,
       navigation = navigation ?? NavigationState(),
       drive = drive ?? DriveState(),
       accountState = accountState ?? AccountState(),
       settingsState = settingsState ?? SettingsState(),
       runtimeState = runtimeState ?? AppRuntimeState(),
       clientRegistry = clientRegistry ?? LanzouClientRegistry() {
    final accountStore = this.accountState.store;
    final settingsStore = this.settingsState.store;
    updateSettings = UpdateSettingsState(settingsStore);
    notificationSettings = NotificationSettingsState(settingsStore);
    navigationAppearanceSettings = NavigationAppearanceSettingsState(
      settingsStore,
      navigation: this.navigation,
      reduceMotion: () => motionReduced,
    );
    themeSettings = ThemeSettingsState(settingsStore);
    transferConnectionSettings = TransferConnectionSettingsState(settingsStore);
    listHomeSettings = ListHomeSettingsState(
      settingsStore,
      trimRecents: this.db.trimRecents,
      activeUid: () => accountStore.activeUid,
    );
    languageClipboardSettings = LanguageClipboardSettingsState(settingsStore);
    cachePageSettings = CachePageSettingsState(settingsStore, this.drive.cache);
    downloadDirectorySettings = DownloadDirectorySettingsState(settingsStore);
  }

  final AppDb db;
  final NavigationState navigation;
  final DriveState drive;
  final AccountState accountState;
  final SettingsState settingsState;
  final AppRuntimeState runtimeState;
  final LanzouClientRegistry clientRegistry;
  late final UpdateSettingsState updateSettings;
  late final NotificationSettingsState notificationSettings;
  late final NavigationAppearanceSettingsState navigationAppearanceSettings;
  late final ThemeSettingsState themeSettings;
  late final TransferConnectionSettingsState transferConnectionSettings;
  late final ListHomeSettingsState listHomeSettings;
  late final LanguageClipboardSettingsState languageClipboardSettings;
  late final CachePageSettingsState cachePageSettings;
  late final DownloadDirectorySettingsState downloadDirectorySettings;

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

  /// 用户设置（全局动画）+ 系统信号合成后的少动效结论。
  bool get motionReduced {
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

  void dispose() {
    accountState.dispose();
    navigation.dispose();
    drive.dispose();
    runtimeState.dispose();
  }
}
