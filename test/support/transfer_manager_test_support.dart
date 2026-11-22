import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/download_target.dart';
import 'package:lancloud/core/notifications.dart';
import 'package:lancloud/core/shared_downloads_gateway.dart';
import 'package:lancloud/core/shared_downloads_storage.dart';
import 'package:lancloud/core/transfer/resumable_downloader.dart';
import 'package:lancloud/core/transfer/transfer_account_port.dart';
import 'package:lancloud/core/transfer/transfer_download_port.dart';
import 'package:lancloud/core/transfer/transfer_store.dart';
import 'package:path/path.dart' as p;

Future<void> waitForTransferCondition(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('等待传输状态超时');
}

class PausingDownloader implements TransferDownloader {
  PausingDownloader(this.payload);

  final List<int> payload;
  final Completer<void> started = Completer<void>();
  final Completer<void> paused = Completer<void>();
  int calls = 0;

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    calls += 1;
    final file = File(partialPath);
    if (calls == 1) {
      final firstPart = payload.sublist(0, payload.length ~/ 2);
      await file.writeAsBytes(firstPart);
      onProgress(firstPart.length, payload.length);
      started.complete();
      await cancelToken.whenCancel;
      paused.complete();
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: url),
        reason: cancelToken.cancelError,
      );
    }

    final existing = await file.exists() ? await file.length() : 0;
    final remaining = payload.sublist(existing);
    await file.writeAsBytes(remaining, mode: FileMode.append);
    onProgress(payload.length, payload.length);
    return TransferDownloadResult(total: payload.length, resumed: existing > 0);
  }
}

class ExpiredLinkDownloader implements TransferDownloader {
  ExpiredLinkDownloader(this.payload);

  final List<int> payload;
  final List<String> urls = <String>[];

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    urls.add(url);
    if (urls.length == 1) {
      final firstPart = payload.sublist(0, 256);
      await File(partialPath).writeAsBytes(firstPart);
      onProgress(firstPart.length, payload.length);
      final request = RequestOptions(path: url);
      throw DioException.badResponse(
        statusCode: 403,
        requestOptions: request,
        response: Response<void>(requestOptions: request, statusCode: 403),
      );
    }
    final file = File(partialPath);
    final existing = await file.exists() ? await file.length() : 0;
    await file.writeAsBytes(payload.sublist(existing), mode: FileMode.append);
    onProgress(payload.length, payload.length);
    return TransferDownloadResult(total: payload.length, resumed: existing > 0);
  }
}

class ImmediateDownloader implements TransferDownloader {
  ImmediateDownloader(this.payload);

  final List<int> payload;

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    await File(partialPath).writeAsBytes(payload);
    onProgress(payload.length, payload.length);
    return TransferDownloadResult(total: payload.length, resumed: false);
  }
}

class ChallengeThenSuccessDownloader implements TransferDownloader {
  ChallengeThenSuccessDownloader({
    required this.challenge,
    required this.payload,
  });

  final List<int> challenge;
  final List<int> payload;
  final List<String> urls = <String>[];

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    urls.add(url);
    final body = urls.length == 1 ? challenge : payload;
    await File(partialPath).writeAsBytes(body);
    onProgress(body.length, body.length);
    return TransferDownloadResult(total: body.length, resumed: false);
  }
}

class FailingDownloader implements TransferDownloader {
  const FailingDownloader();

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) {
    throw DioException.connectionError(
      requestOptions: RequestOptions(path: url),
      reason: 'Connection closed while receiving data',
    );
  }
}

class ImmediateUploadAccountPort implements TransferAccountPort {
  final LanzouClient _client = ImmediateUploadClient();

  @override
  String? get activeUid => 'u1';

  @override
  bool hasAccount(String uid) => uid == 'u1';

  @override
  LanzouClient clientFor(String uid) => _client;

  @override
  LanzouClient get publicClient => throw UnimplementedError('上传测试不需要公开客户端');
}

class ImmediateUploadClient extends LanzouClient {
  ImmediateUploadClient() : super(uid: 'u1');

  @override
  Future<void> uploadFile({
    required String name,
    required String folderId,
    String? path,
    Stream<List<int>> Function()? streamFactory,
    int? size,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final total = size ?? 0;
    onProgress?.call(total, total);
  }
}

class BlockingUploadAccountPort implements TransferAccountPort {
  final BlockingUploadClient client = BlockingUploadClient();

  @override
  String? get activeUid => 'u1';

  @override
  bool hasAccount(String uid) => uid == 'u1';

  @override
  LanzouClient clientFor(String uid) => client;

  @override
  LanzouClient get publicClient => throw UnimplementedError('上传测试不需要公开客户端');
}

class BlockingUploadClient extends LanzouClient {
  BlockingUploadClient() : super(uid: 'u1');

  final Completer<void> started = Completer<void>();

  @override
  Future<void> uploadFile({
    required String name,
    required String folderId,
    String? path,
    Stream<List<int>> Function()? streamFactory,
    int? size,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    started.complete();
    await cancelToken?.whenCancel;
    throw DioException.requestCancelled(
      requestOptions: RequestOptions(path: LanzouClient.uploadUrl),
      reason: cancelToken?.cancelError,
    );
  }
}

class BurstProgressDownloader implements TransferDownloader {
  BurstProgressDownloader(this.payload);

  final List<int> payload;
  final Completer<void> started = Completer<void>();
  final Completer<void> emitProgress = Completer<void>();
  final Completer<void> progressBurst = Completer<void>();
  final Completer<void> finish = Completer<void>();

  @override
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    started.complete();
    await emitProgress.future;
    onProgress(1, payload.length);
    onProgress(2, payload.length);
    onProgress(payload.length, payload.length);
    progressBurst.complete();
    await finish.future;
    await File(partialPath).writeAsBytes(payload);
    return TransferDownloadResult(total: payload.length, resumed: false);
  }
}

class RecordingNotificationSink implements TransferNotificationSink {
  final List<TransferNotificationSnapshot> snapshots =
      <TransferNotificationSnapshot>[];
  final List<String> cancellations = <String>[];

  @override
  void showTransferTask(TransferNotificationSnapshot snapshot) {
    snapshots.add(snapshot);
  }

  @override
  void cancelTransferTask(String taskId) {
    cancellations.add(taskId);
  }
}

class BlockingSharedDownloads implements SharedDownloadsGateway {
  BlockingSharedDownloads(this.total);

  final int total;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<String?> defaultDirectoryPath() async => null;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<SharedDownloadedFile> save({
    required String sourcePath,
    required String fileName,
    required String mime,
    String jobId = '',
    void Function(int copied, int total)? onProgress,
  }) async {
    started.complete();
    onProgress?.call(256, total);
    await release.future;
    onProgress?.call(total, total);
    return SharedDownloadedFile(
      uri: 'content://saved/$fileName',
      name: fileName,
    );
  }
}

class FakeTransferStore implements TransferStore {
  FakeTransferStore([this.rows = const <Map<String, Object?>>[]]);

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
    String folderName = '',
    String referer = '',
    String pwd = '',
    String localPath = '',
    String account = '',
  }) async {}

  @override
  Future<void> deleteTransfer(String id) async {}

  @override
  Future<void> deleteTransfers(List<String> ids) async {}
}

class FakeTransferAccountPort implements TransferAccountPort {
  @override
  String? get activeUid => 'u1';

  @override
  bool hasAccount(String uid) => uid == 'u1';

  @override
  LanzouClient clientFor(String uid) =>
      throw UnimplementedError('暂停恢复测试不需要账号客户端');

  @override
  LanzouClient get publicClient => throw UnimplementedError('本会话内已有直链，不需要重新解析');
}

class FakeTransferDownloadPort implements TransferDownloadPort {
  const FakeTransferDownloadPort(
    this.directory, {
    this.mode = DownloadTargetMode.fixedDirectory,
  });

  final String directory;
  final DownloadTargetMode mode;

  @override
  Future<String> partialFilePath(
    String taskId,
    String name, {
    required bool staged,
  }) async => p.join(directory, '$taskId.part');

  @override
  String? get safTreeUri => null;

  @override
  Future<DownloadTargetMode> targetMode() async => mode;

  @override
  Future<String> uniqueSavePath(String name) async => p.join(directory, name);
}
