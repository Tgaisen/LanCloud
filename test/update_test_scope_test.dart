import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/account_session.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/backup_service_provider.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/data/settings_store_provider.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/download_directory_settings_state.dart';
import 'package:lancloud/core/language_clipboard_settings_state.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/notification_settings_state.dart';
import 'package:lancloud/core/theme_settings_state.dart';
import 'package:lancloud/core/transfer_connection_settings_state.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<ReleaseInfo>> _noReleases() async => const [];

/// 创建只包含更新试点依赖的测试容器。
ProviderContainer createUpdateContainer({
  required SettingsStore settings,
  UpdateFetcher fetch = _noReleases,
  UpdateClock? clock,
}) {
  return ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWithValue(settings),
      updateFetcherProvider.overrideWithValue(fetch),
      if (clock != null) updateClockProvider.overrideWithValue(clock),
    ],
  );
}

/// 同时提供旧 Provider 与 Riverpod 试点作用域。
Widget updateTestTree({
  required AppController app,
  required ProviderContainer container,
  required Widget child,
}) => updateEnvironmentTestTree(
  environment: app.environment,
  container: container,
  child: child,
);

Widget updateEnvironmentTestTree({
  required AppEnvironment environment,
  required ProviderContainer container,
  required Widget child,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: ProviderScope(
      overrides: [
        accountStateProvider.overrideWithValue(environment.accountState),
        appDbProvider.overrideWithValue(environment.db),
        accountSessionProvider.overrideWithValue(environment.accountSession),
        navigationAppearanceSettingsStateProvider.overrideWithValue(
          environment.navigationAppearanceSettings,
        ),
        navigationStateProvider.overrideWithValue(environment.navigation),
      ],
      child: child,
    ),
  );
}

/// 同时提供旧 Provider 与页面已迁移状态使用的 Riverpod 作用域。
Widget appTestTree({
  required AppController app,
  required Widget child,
  BackupService? backupService,
}) => appEnvironmentTestTree(
  environment: app.environment,
  child: child,
  backupService: backupService,
);

/// 用应用环境提供页面已迁移状态使用的 Riverpod 作用域。
Widget appEnvironmentTestTree({
  required AppEnvironment environment,
  required Widget child,
  BackupService? backupService,
}) {
  return ProviderScope(
    overrides: [
      if (backupService != null)
        backupServiceProvider.overrideWithValue(backupService),
      accountStateProvider.overrideWithValue(environment.accountState),
      accountSessionProvider.overrideWithValue(environment.accountSession),
      appDbProvider.overrideWithValue(environment.db),
      settingsStoreProvider.overrideWithValue(environment.settingsState.store),
      driveStateProvider.overrideWithValue(environment.drive),
      cachePageSettingsStateProvider.overrideWithValue(
        environment.cachePageSettings,
      ),
      navigationAppearanceSettingsStateProvider.overrideWithValue(
        environment.navigationAppearanceSettings,
      ),
      navigationStateProvider.overrideWithValue(environment.navigation),
      themeSettingsStateProvider.overrideWithValue(environment.themeSettings),
      listHomeSettingsStateProvider.overrideWithValue(
        environment.listHomeSettings,
      ),
      transferConnectionSettingsStateProvider.overrideWithValue(
        environment.transferConnectionSettings,
      ),
      downloadDirectorySettingsStateProvider.overrideWithValue(
        environment.downloadDirectorySettings,
      ),
      notificationSettingsStateProvider.overrideWithValue(
        environment.notificationSettings,
      ),
      languageClipboardSettingsStateProvider.overrideWithValue(
        environment.languageClipboardSettings,
      ),
    ],
    child: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('测试容器通过 provider override 注入网络假数据', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsStore()..updateChannel = 'stable';
    var calls = 0;
    final container = createUpdateContainer(
      settings: settings,
      fetch: () async {
        calls++;
        return const [];
      },
    );
    addTearDown(container.dispose);
    final service = container.read(updateServiceProvider.notifier);
    await service.initialize();

    expect(await service.check(), isTrue);
    expect(calls, 1);
  });
}
