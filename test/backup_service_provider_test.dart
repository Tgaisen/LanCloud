import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_dependencies.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/backup_service_provider.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/settings_store.dart';

BackupDependencies backupDependenciesFor(AppController app) =>
    BackupStoreDependencies(
      accounts: app.accountState.store,
      settings: app.settingsState.store,
      db: app.db,
      reloadCallback: app.reloadFromStorage,
    );

void main() {
  test('备份服务必须由应用入口覆盖并保持同一实例', () {
    final empty = ProviderContainer();
    addTearDown(empty.dispose);
    expect(
      () => empty.read(backupServiceProvider),
      throwsA(isA<ProviderException>()),
    );

    final app = AppController();
    final service = BackupService(backupDependenciesFor(app));
    final container = ProviderContainer(
      overrides: [
        backupServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(app.dispose);
    addTearDown(container.dispose);
    expect(container.read(backupServiceProvider), same(service));
  });

  test('BackupStoreDependencies 直接转发存储与重载回调', () async {
    final accounts = AccountStore();
    final settings = SettingsStore();
    var reloads = 0;
    final dependencies = BackupStoreDependencies(
      accounts: accounts,
      settings: settings,
      db: AppDb.instance,
      reloadCallback: () async => reloads += 1,
    );

    expect(dependencies.accounts, same(accounts));
    expect(dependencies.settings, same(settings));
    expect(dependencies.db, same(AppDb.instance));
    await dependencies.reloadFromStorage();
    expect(reloads, 1);
  });
}
