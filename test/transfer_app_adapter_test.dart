import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_target.dart';
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
  _FakeTransferAdapter(this.transferStore);

  @override
  final TransferStore transferStore;

  @override
  final AccountStore accounts = AccountStore();

  @override
  final SettingsStore settings = SettingsStore();

  @override
  String? get activeUid => null;

  @override
  LanzouClient get publicClient =>
      throw UnimplementedError('测试恢复流程不应解析分享链接');

  @override
  LanzouClient clientFor(String uid) =>
      throw UnimplementedError('测试恢复流程不应创建账号客户端');

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
    expect(app.accounts, same(app.accountState.store));
    expect(app.settings, same(app.settingsState.store));
    expect(app.publicClient, same(app.clientRegistry.publicClient));
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
    final manager = TransferManager(_FakeTransferAdapter(store));
    addTearDown(manager.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(manager.tasks, hasLength(1));
    expect(manager.tasks.single.id, 'd1');
    expect(manager.tasks.single.status, TransferStatus.done);
  });
}
