import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_state.dart';
import 'account_session.dart';
import 'app_controller.dart';
import 'app_log.dart';
import 'app_log_provider.dart';
import 'app_runtime_state.dart';
import 'api/lanzou_client_registry.dart';
import 'backup/backup_dependencies.dart';
import 'backup/backup_service.dart';
import 'backup/backup_service_provider.dart';
import 'cache_page_settings_state.dart';
import 'data/app_db_provider.dart';
import 'download_directory_settings_state.dart';
import 'download_path_service.dart';
import 'drive_state.dart';
import 'language_clipboard_settings_state.dart';
import 'list_home_settings_state.dart';
import 'navigation_appearance_settings_state.dart';
import 'navigation_state.dart';
import 'notification_settings_state.dart';
import 'notifications.dart';
import 'notifications_provider.dart';
import 'settings_state.dart';
import 'shared_downloads_gateway.dart';
import 'theme_settings_state.dart';
import 'transfer/transfer_account_port.dart';
import 'transfer/transfer_dependencies.dart';
import 'transfer/transfer_download_port.dart';
import 'transfer/transfer_manager_provider.dart';
import 'transfer/transfer_settings_port.dart';
import 'transfer/transfer_store.dart';
import 'transfer_connection_settings_state.dart';
import 'update/update_settings_state.dart';

/// 应用启动组合根：把已初始化的应用对象装配到 Riverpod 容器。
///
/// 平台服务初始化仍由 `main()` 控制；本类只负责对象组合，不触发启动流程。
final class AppCompositionRoot {
  AppCompositionRoot({
    required this.app,
    required this.sharedDownloads,
    required this.downloadPaths,
  });

  final AppController app;
  final SharedDownloadsGateway sharedDownloads;
  final DownloadPathService downloadPaths;

  late final TransferDependencies transferDependencies = TransferDependencies(
    store: AppDbTransferStore(database: app.db),
    accounts: AppTransferAccountPort(
      accounts: app.accountState.store,
      clients: app.clientRegistry,
    ),
    download: DefaultTransferDownloadPort(
      downloadPaths: downloadPaths,
      sharedDownloads: sharedDownloads,
      settings: app.settingsState.store,
    ),
    settings: StoreTransferSettingsPort(app.settingsState.store),
  );

  late final BackupService backupService = BackupService.of(
    BackupStoreDependencies(
      accounts: app.accountState.store,
      settings: app.settingsState.store,
      db: app.db,
      reloadCallback: app.reloadFromStorage,
    ),
  );

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(app.db),
        appLogProvider.overrideWithValue(AppLog.instance),
        backupServiceProvider.overrideWithValue(backupService),
        lanzouClientRegistryProvider.overrideWithValue(app.clientRegistry),
        navigationStateProvider.overrideWithValue(app.navigation),
        driveStateProvider.overrideWithValue(app.drive),
        appRuntimeStateProvider.overrideWithValue(app.runtimeState),
        accountStateProvider.overrideWithValue(app.accountState),
        accountSessionProvider.overrideWithValue(app.accountSession),
        settingsStateProvider.overrideWithValue(app.settingsState),
        updateSettingsStateProvider.overrideWithValue(app.updateSettings),
        navigationAppearanceSettingsStateProvider.overrideWithValue(
          app.navigationAppearanceSettings,
        ),
        notificationSettingsStateProvider.overrideWithValue(
          app.notificationSettings,
        ),
        themeSettingsStateProvider.overrideWithValue(app.themeSettings),
        transferConnectionSettingsStateProvider.overrideWithValue(
          app.transferConnectionSettings,
        ),
        listHomeSettingsStateProvider.overrideWithValue(app.listHomeSettings),
        languageClipboardSettingsStateProvider.overrideWithValue(
          app.languageClipboardSettings,
        ),
        cachePageSettingsStateProvider.overrideWithValue(app.cachePageSettings),
        downloadDirectorySettingsStateProvider.overrideWithValue(
          app.downloadDirectorySettings,
        ),
        notificationServiceProvider.overrideWithValue(
          NotificationService.instance,
        ),
        downloadPathServiceProvider.overrideWithValue(downloadPaths),
        sharedDownloadsGatewayProvider.overrideWithValue(sharedDownloads),
        transferDependenciesProvider.overrideWithValue(transferDependencies),
      ],
    );
  }
}
