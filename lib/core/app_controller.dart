import 'package:flutter/foundation.dart';

import 'api/lanzou_client_registry.dart';
import 'account_state.dart';
import 'account_login.dart';
import 'account_session.dart';
import 'app_environment.dart';
import 'app_runtime_state.dart';
import 'app_startup.dart';
import 'data/app_db.dart';
import 'download_directory_settings_state.dart';
import 'drive_state.dart';
import 'cache_page_settings_state.dart';
import 'navigation_state.dart';
import 'navigation_appearance_settings_state.dart';
import 'notification_settings_state.dart';
import 'list_home_settings_state.dart';
import 'language_clipboard_settings_state.dart';
import 'settings_state.dart';
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
  }) : environment = AppEnvironment(
         navigation: navigation,
         drive: drive,
         accountState: accountState,
         settingsState: settingsState,
         runtimeState: runtimeState,
       ) {
    this.navigation.addListener(notifyListeners);
    navigationAppearanceSettings.revision.addListener(notifyListeners);
    themeSettings.revision.addListener(notifyListeners);
    languageClipboardSettings.revision.addListener(notifyListeners);
    listHomeSettings.revision.addListener(notifyListeners);
    downloadDirectorySettings.revision.addListener(notifyListeners);
    this.accountState.addListener(notifyListeners);
    startup = AppStartup(environment: environment, onChanged: notifyListeners);
  }

  final AppEnvironment environment;
  late final AppStartup startup;

  AccountState get accountState => environment.accountState;
  SettingsState get settingsState => environment.settingsState;
  AppRuntimeState get runtimeState => environment.runtimeState;
  UpdateSettingsState get updateSettings => environment.updateSettings;
  NotificationSettingsState get notificationSettings =>
      environment.notificationSettings;
  NavigationAppearanceSettingsState get navigationAppearanceSettings =>
      environment.navigationAppearanceSettings;
  ThemeSettingsState get themeSettings => environment.themeSettings;
  TransferConnectionSettingsState get transferConnectionSettings =>
      environment.transferConnectionSettings;
  ListHomeSettingsState get listHomeSettings => environment.listHomeSettings;
  LanguageClipboardSettingsState get languageClipboardSettings =>
      environment.languageClipboardSettings;
  CachePageSettingsState get cachePageSettings => environment.cachePageSettings;
  DownloadDirectorySettingsState get downloadDirectorySettings =>
      environment.downloadDirectorySettings;

  AppDb get db => environment.db;
  NavigationState get navigation => environment.navigation;
  DriveState get drive => environment.drive;

  LanzouClientRegistry get clientRegistry => environment.clientRegistry;
  AccountLogin get accountLogin => environment.accountLogin;
  AccountSession get accountSession => environment.accountSession;

  Future<void> init() => startup.initialize();

  Future<void> reloadFromStorage() => startup.reloadFromStorage();

  @override
  void dispose() {
    accountState.removeListener(notifyListeners);
    navigation.removeListener(notifyListeners);
    navigationAppearanceSettings.revision.removeListener(notifyListeners);
    themeSettings.revision.removeListener(notifyListeners);
    languageClipboardSettings.revision.removeListener(notifyListeners);
    listHomeSettings.revision.removeListener(notifyListeners);
    downloadDirectorySettings.revision.removeListener(notifyListeners);
    environment.dispose();
    super.dispose();
  }

}
