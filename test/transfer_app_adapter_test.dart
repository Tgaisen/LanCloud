import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/transfer/transfer_account_port.dart';
import 'package:lancloud/core/transfer/transfer_app_adapter.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
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

class _FakeTransferAdapter implements TransferAppAdapter {
  _FakeTransferAdapter(this.transferStore, this.transferAccounts);

  @override
  final TransferStore transferStore;

  @override
  final TransferAccountPort transferAccounts;

  @override
  final SettingsStore settings = SettingsStore();

  @override
  Future<DownloadTargetMode> downloadTargetMode() async =>
      DownloadTargetMode.fixedDirectory;

  @override
  String? get safDownloadTree => null;

  @override
  Future<String> safTempFilePath(String taskId, String name) async =>
      throw UnimplementedError('测试恢复流程不应写下载文件');

  @override
  Future<String> uniqueSavePath(String name) async =>
      throw UnimplementedError('测试恢复流程不应写下载文件');
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('AppController 实现 TransferManager 的最小依赖边界', () {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final app = AppController();
    addTearDown(app.dispose);

    expect(app, isA<TransferAppAdapter>());
    expect(app.db, same(AppDb.instance));
    final store = app.transferStore;
    expect(store, isA<AppDbTransferStore>());
    if (store is AppDbTransferStore) {
      expect(store.database, same(AppDb.instance));
    }
    final accounts = app.transferAccounts;
    expect(accounts, isA<AppTransferAccountPort>());
    if (accounts is AppTransferAccountPort) {
      expect(accounts.accounts, same(app.accountState.store));
      expect(accounts.clients, same(app.clientRegistry));
    }
    expect(app.settings, same(app.settingsState.store));
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
    final manager = TransferManager(
      _FakeTransferAdapter(store, _FakeTransferAccountPort()),
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
}
