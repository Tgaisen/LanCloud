import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/app_composition_root.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/backup_service_provider.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_path_service.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/shared_downloads_gateway.dart';
import 'package:lancloud/core/transfer/transfer_account_port.dart';
import 'package:lancloud/core/transfer/transfer_dependencies.dart';
import 'package:lancloud/core/transfer/transfer_download_port.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/core/transfer/transfer_settings_port.dart';
import 'package:lancloud/core/transfer/transfer_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransferStore implements TransferStore {
  _FakeTransferStore(this.rows);

  final List<Map<String, Object?>> rows;

  @override
  Future<List<Map<String, Object?>>> loadTransfers() async => rows;

  @override
  Future<void> saveTransfer({
    required String id,
    required String kind,
    required String name,
    required String status,
    int total = 0,
    int received = 0,
    String error = '',
    String savedPath = '',
    String ref = '',
    String folderId = '',
    String referer = '',
    String pwd = '',
    String localPath = '',
    String account = '',
  }) async {}

  @override
  Future<void> deleteTransfer(String id) async {}

  @override
  Future<void> deleteTransfers(List<String> ids) async {}

  @override
  Future<void> markDownloaded({
    required String ref,
    required String name,
    String path = '',
  }) async {}
}

class _FixedDownloadPathService implements DownloadPathService {
  const _FixedDownloadPathService(this.path);

  final String path;

  @override
  Future<String> defaultDownloadDirPath() async => path;
}

class _FakeTransferAccountPort implements TransferAccountPort {
  @override
  String? get activeUid => null;

  @override
  bool hasAccount(String uid) => false;

  @override
  LanzouClient clientFor(String uid) =>
      throw UnimplementedError('测试恢复流程不应创建账号客户端');

  @override
  LanzouClient get publicClient =>
      throw UnimplementedError('测试恢复流程不应解析分享链接');
}

class _FakeTransferDownloadPort implements TransferDownloadPort {
  @override
  Future<DownloadTargetMode> targetMode() async =>
      DownloadTargetMode.fixedDirectory;

  @override
  String? get safTreeUri => null;

  @override
  Future<String> safTempFilePath(String taskId, String name) async =>
      throw UnimplementedError('测试恢复流程不应写下载文件');

  @override
  Future<String> uniqueSavePath(String name) async =>
      throw UnimplementedError('测试恢复流程不应写下载文件');
}

TransferManager buildTransferManager(AppController app) {
  const sharedDownloads = PlatformSharedDownloadsGateway();
  final downloadPaths = PlatformDownloadPathService(
    sharedDownloads: sharedDownloads,
  );
  final environment = app.environment;
  final composition = AppCompositionRoot(
    environment: environment,
    reloadFromStorage: app.reloadFromStorage,
    sharedDownloads: sharedDownloads,
    downloadPaths: downloadPaths,
  );
  return TransferManager.withDependencies(
    composition.transferDependencies,
    sharedDownloads: sharedDownloads,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('生产传输依赖可从应用级对象直接组装', () {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const sharedDownloads = PlatformSharedDownloadsGateway();
    final downloadPaths = PlatformDownloadPathService(
      sharedDownloads: sharedDownloads,
    );
    final app = AppController();
    addTearDown(app.dispose);

    expect(app.db, same(AppDb.instance));
    final store = AppDbTransferStore(database: app.db);
    expect(store, isA<AppDbTransferStore>());
    expect(store.database, same(AppDb.instance));
    final accounts = AppTransferAccountPort(
      accounts: app.accountState.store,
      clients: app.clientRegistry,
    );
    expect(accounts, isA<AppTransferAccountPort>());
    expect(accounts.accounts, same(app.accountState.store));
    expect(accounts.clients, same(app.clientRegistry));
    final download = DefaultTransferDownloadPort(
      downloadPaths: downloadPaths,
      sharedDownloads: sharedDownloads,
      settings: app.settingsState.store,
    );
    expect(download, isA<DefaultTransferDownloadPort>());
    expect(download.downloadPaths, same(downloadPaths));
    expect(download.sharedDownloads, same(sharedDownloads));
    expect(download.settings, same(app.settingsState.store));
    final settings = StoreTransferSettingsPort(app.settingsState.store);
    final dependencies = TransferDependencies(
      store: store,
      accounts: accounts,
      download: download,
      settings: settings,
    );
    expect(dependencies.store, same(store));
    expect(dependencies.accounts, same(accounts));
    expect(dependencies.download, same(download));
    expect(dependencies.settings, same(settings));
  });

  test('启动组合根复用应用级状态与依赖', () {
    BackupService.instance = null;
    addTearDown(() => BackupService.instance = null);
    const sharedDownloads = PlatformSharedDownloadsGateway();
    final downloadPaths = PlatformDownloadPathService(
      sharedDownloads: sharedDownloads,
    );
    final app = AppController();
    addTearDown(app.dispose);
    final environment = app.environment;
    final composition = AppCompositionRoot(
      environment: environment,
      reloadFromStorage: app.reloadFromStorage,
      sharedDownloads: sharedDownloads,
      downloadPaths: downloadPaths,
    );
    final container = composition.createContainer();
    addTearDown(container.dispose);

    expect(container.read(appDbProvider), same(environment.db));
    expect(
      container.read(backupServiceProvider),
      same(composition.backupService),
    );
    expect(
      container.read(transferDependenciesProvider),
      same(composition.transferDependencies),
    );
    expect(
      composition.transferDependencies.store,
      isA<AppDbTransferStore>(),
    );
    expect(
      (composition.transferDependencies.store as AppDbTransferStore).database,
      same(environment.db),
    );
    expect(
      composition.backupService.dependencies.accounts,
      same(environment.accountState.store),
    );
    expect(
      composition.backupService.dependencies.settings,
      same(environment.settingsState.store),
    );
    expect(composition.backupService.dependencies.db, same(environment.db));
  });

  test('TransferManager 可从注入的存储端口恢复任务', () async {
    final store = _FakeTransferStore([
      {
        'id': 'd1',
        'kind': 'download',
        'name': '示例文件',
        'status': 'done',
        'total': 10,
        'received': 10,
        'account': '',
        'folder_id': '',
        'local_path': '',
        'referer': '',
        'pwd': '',
        'ref': '',
        'saved_path': '/tmp/example',
        'error': '',
      },
    ]);
    final manager = TransferManager.withDependencies(
      TransferDependencies(
        store: store,
        accounts: _FakeTransferAccountPort(),
        download: _FakeTransferDownloadPort(),
        settings: StoreTransferSettingsPort(SettingsStore()),
      ),
    );
    addTearDown(manager.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single.id, 'd1');
    expect(manager.tasks.single.status, TransferStatus.done);
  });

  test('账号端口从同一账号存储和客户端注册表解析', () {
    final accounts = AccountStore()
      ..accounts.add(Account(uid: 'u1', cookie: 'cookie'))
      ..activeUid = 'u1';
    final clients = LanzouClientRegistry();
    final port = AppTransferAccountPort(accounts: accounts, clients: clients);

    expect(port.activeUid, 'u1');
    expect(port.hasAccount('u1'), isTrue);
    expect(port.hasAccount('missing'), isFalse);
    expect(port.clientFor('u1'), same(clients.clientFor('u1')));
    expect(port.publicClient, same(clients.publicClient));
  });

  test('下载回调端口保持目标模式与路径委托', () async {
    final port = CallbackTransferDownloadPort(
      targetMode: () async => DownloadTargetMode.safDirectory,
      safTreeUri: () => 'content://tree/example',
      safTempFilePath: (taskId, name) async => '/tmp/$taskId$name',
      uniqueSavePath: (name) async => '/downloads/$name',
    );

    expect(await port.targetMode(), DownloadTargetMode.safDirectory);
    expect(port.safTreeUri, 'content://tree/example');
    expect(await port.safTempFilePath('t1', 'a.bin'), '/tmp/t1a.bin');
    expect(await port.uniqueSavePath('a.bin'), '/downloads/a.bin');
  });

  test('默认下载端口在固定目录中生成不冲突路径', () async {
    final dir = Directory.systemTemp.createTempSync('lancloud-download-port');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    File(p.join(dir.path, 'a.txt')).writeAsStringSync('existing');
    final settings = SettingsStore()..downloadDir = dir.path;
    final port = DefaultTransferDownloadPort(
      downloadPaths: _FixedDownloadPathService(dir.path),
      sharedDownloads: const PlatformSharedDownloadsGateway(),
      settings: settings,
    );

    expect(
      await port.uniqueSavePath('a.txt'),
      p.join(dir.path, 'a(1).txt'),
    );
  });

  test('设置端口实时读取传输相关字段', () {
    final store = SettingsStore()
      ..maxUploads = 2
      ..maxDownloads = 4
      ..notifyProgress = false
      ..notifyDone = false;
    final port = StoreTransferSettingsPort(store);

    expect(port.maxUploads, 2);
    expect(port.maxDownloads, 4);
    expect(port.notifyProgress, isFalse);
    expect(port.notifyDone, isFalse);
  });

  test('transferManagerProvider 提供应用级共享实例', () async {
    final container = ProviderContainer(
      overrides: [
        transferDependenciesProvider.overrideWithValue(
          TransferDependencies(
            store: _FakeTransferStore(const []),
            accounts: _FakeTransferAccountPort(),
            download: _FakeTransferDownloadPort(),
            settings: StoreTransferSettingsPort(SettingsStore()),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final first = container.read(transferManagerProvider);
    final second = container.read(transferManagerProvider);

    expect(second, same(first));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
}
