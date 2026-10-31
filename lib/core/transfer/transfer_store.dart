import '../data/app_db.dart';

/// `TransferManager` 需要的传输持久化能力。
abstract interface class TransferStore {
  Future<List<Map<String, Object?>>> loadTransfers();

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
  });

  Future<void> deleteTransfer(String id);
  Future<void> deleteTransfers(List<String> ids);

  Future<void> markDownloaded({
    required String ref,
    required String name,
    String path = '',
  });
}

/// 把既有 [AppDb] 适配为传输持久化端口。
class AppDbTransferStore implements TransferStore {
  AppDbTransferStore({AppDb? database}) : database = database ?? AppDb.instance;

  final AppDb database;

  @override
  Future<List<Map<String, Object?>>> loadTransfers() =>
      database.loadTransfers();

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
  }) => database.saveTransfer(
    id: id,
    kind: kind,
    name: name,
    status: status,
    total: total,
    received: received,
    error: error,
    savedPath: savedPath,
    ref: ref,
    folderId: folderId,
    referer: referer,
    pwd: pwd,
    localPath: localPath,
    account: account,
  );

  @override
  Future<void> deleteTransfer(String id) => database.deleteTransfer(id);

  @override
  Future<void> deleteTransfers(List<String> ids) =>
      database.deleteTransfers(ids);

  @override
  Future<void> markDownloaded({
    required String ref,
    required String name,
    String path = '',
  }) => database.markDownloaded(ref: ref, name: name, path: path);
}
