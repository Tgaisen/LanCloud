import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/transfer/resumable_downloader.dart';

void main() {
  group('DioTransferDownloader', () {
    late Directory tempDir;
    late File partialFile;
    late Dio dio;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lancloud-resume-test');
      partialFile = File('${tempDir.path}/download.part');
      dio = Dio();
    });

    tearDown(() async {
      dio.close(force: true);
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('should 下载完整文件并报告总大小', () async {
      final payload = List<int>.generate(4096, (index) => index % 251);
      final requestedRange = Completer<String?>();
      final server = await _startServer((request) async {
        requestedRange.complete(request.headers.value('range'));
        await _writeResponse(request.response, payload);
      });
      addTearDown(() => server.close(force: true));
      final progress = <int>[];

      final result = await const DioTransferDownloader().download(
        dio: dio,
        url: 'http://${server.address.host}:${server.port}/file',
        partialPath: partialFile.path,
        expectedTotal: payload.length,
        cancelToken: CancelToken(),
        headers: const <String, String>{'Referer': 'https://example.com/share'},
        receiveTimeout: const Duration(seconds: 5),
        onProgress: (received, total) => progress.add(received),
      );

      expect(await requestedRange.future, isNull);
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isFalse);
      expect(progress.last, payload.length);
    });

    test('should 从已有 .part 文件发送 Range 并追加剩余内容', () async {
      final payload = List<int>.generate(4096, (index) => index % 241);
      final half = payload.length ~/ 2;
      await partialFile.writeAsBytes(payload.sublist(0, half));
      final requestedRange = Completer<String?>();
      final server = await _startServer((request) async {
        requestedRange.complete(request.headers.value('range'));
        final start = int.parse(
          RegExp(r'bytes=(\d+)-')
              .firstMatch(request.headers.value('range')!)!
              .group(1)!,
        );
        await _writeResponse(
          request.response,
          payload.sublist(start),
          statusCode: HttpStatus.partialContent,
          contentRange: 'bytes $start-${payload.length - 1}/${payload.length}',
        );
      });
      addTearDown(() => server.close(force: true));
      final progress = <(int, int)>[];

      final result = await const DioTransferDownloader().download(
        dio: dio,
        url: 'http://${server.address.host}:${server.port}/file',
        partialPath: partialFile.path,
        expectedTotal: payload.length,
        cancelToken: CancelToken(),
        headers: const <String, String>{},
        receiveTimeout: const Duration(seconds: 5),
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(await requestedRange.future, 'bytes=$half-');
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isTrue);
      expect(progress.last, (payload.length, payload.length));
    });

    test('should 在服务器忽略 Range 时截断 .part 并从头写入', () async {
      final payload = List<int>.generate(2048, (index) => index % 199);
      await partialFile.writeAsBytes(const <int>[1, 2, 3, 4]);
      final requestedRange = Completer<String?>();
      final server = await _startServer((request) async {
        requestedRange.complete(request.headers.value('range'));
        await _writeResponse(request.response, payload);
      });
      addTearDown(() => server.close(force: true));

      final result = await const DioTransferDownloader().download(
        dio: dio,
        url: 'http://${server.address.host}:${server.port}/file',
        partialPath: partialFile.path,
        expectedTotal: payload.length,
        cancelToken: CancelToken(),
        headers: const <String, String>{},
        receiveTimeout: const Duration(seconds: 5),
        onProgress: (_, _) {},
      );

      expect(await requestedRange.future, 'bytes=4-');
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isFalse);
    });

    test('should 在不匹配的 206 后无 Range 重新请求完整文件', () async {
      final payload = List<int>.generate(3072, (index) => index % 223);
      final half = payload.length ~/ 2;
      await partialFile.writeAsBytes(payload.sublist(0, half));
      final ranges = <String?>[];
      final server = await _startServer((request) async {
        final range = request.headers.value('range');
        ranges.add(range);
        if (range != null) {
          await _writeResponse(
            request.response,
            payload.sublist(1),
            statusCode: HttpStatus.partialContent,
            contentRange: 'bytes 1-${payload.length - 1}/${payload.length}',
          );
          return;
        }
        await _writeResponse(request.response, payload);
      });
      addTearDown(() => server.close(force: true));

      final result = await const DioTransferDownloader().download(
        dio: dio,
        url: 'http://${server.address.host}:${server.port}/file',
        partialPath: partialFile.path,
        expectedTotal: payload.length,
        cancelToken: CancelToken(),
        headers: const <String, String>{},
        receiveTimeout: const Duration(seconds: 5),
        onProgress: (_, _) {},
      );

      expect(ranges, <String?>['bytes=$half-', null]);
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
    });
  });
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    unawaited(
      handler(request).catchError((Object error, StackTrace stackTrace) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
        Error.throwWithStackTrace(error, stackTrace);
      }),
    );
  });
  return server;
}

Future<void> _writeResponse(
  HttpResponse response,
  List<int> payload, {
  int statusCode = HttpStatus.ok,
  String? contentRange,
}) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.binary;
  response.contentLength = payload.length;
  if (contentRange != null) {
    response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
  }
  response.add(payload);
  await response.close();
}
