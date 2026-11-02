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

    test('should 用多个精确 Range 并发下载分片', () async {
      final payload = List<int>.generate(4096, (index) => index % 233);
      final ranges = <String>[];
      final bothStarted = Completer<void>();
      final release = Completer<void>();
      var active = 0;
      var maxActive = 0;
      final server = await _startServer((request) async {
        final range = request.headers.value('range');
        if (range == null) {
          fail('分片请求必须带 Range');
        }
        ranges.add(range);
        if (range == 'bytes=0-0') {
          await _writeResponse(
            request.response,
            payload.sublist(0, 1),
            statusCode: HttpStatus.partialContent,
            contentRange: 'bytes 0-0/${payload.length}',
          );
          return;
        }

        final bounds = _rangeBounds(range);
        active += 1;
        if (active > maxActive) maxActive = active;
        if (active == 2 && !bothStarted.isCompleted) bothStarted.complete();
        await release.future;
        active -= 1;
        await _writeResponse(
          request.response,
          payload.sublist(bounds.start, bounds.end + 1),
          statusCode: HttpStatus.partialContent,
          contentRange: 'bytes ${bounds.start}-${bounds.end}/${payload.length}',
        );
      });
      addTearDown(() => server.close(force: true));

      final download =
          const DioTransferDownloader(
            segmentConnections: 2,
            segmentSize: 2048,
            minimumSegmentedBytes: 1,
          ).download(
            dio: dio,
            url: 'http://${server.address.host}:${server.port}/file',
            partialPath: partialFile.path,
            expectedTotal: payload.length,
            cancelToken: CancelToken(),
            headers: const <String, String>{},
            receiveTimeout: const Duration(seconds: 5),
            onProgress: (_, _) {},
          );

      await bothStarted.future.timeout(const Duration(seconds: 2));
      release.complete();
      final result = await download;

      expect(maxActive, 2);
      expect(ranges.where((range) => range != 'bytes=0-0').toSet(), <String>{
        'bytes=0-2047',
        'bytes=2048-4095',
      });
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isFalse);
      final metadata = File(
        DioTransferDownloader.metadataPathFor(partialFile.path),
      );
      expect(await metadata.exists(), isTrue);
      await DioTransferDownloader.deleteState(partialFile.path);
      expect(await partialFile.exists(), isFalse);
      expect(await metadata.exists(), isFalse);
    });

    test('should 从分片检查点继续下载', () async {
      final payload = List<int>.generate(4096, (index) => index % 229);
      final ranges = <int, List<String>>{1: <String>[], 2: <String>[]};
      var failPartialResponse = true;
      final server = await _startServer((request) async {
        final range = request.headers.value('range');
        if (range == null) fail('分片请求必须带 Range');
        ranges[failPartialResponse ? 1 : 2]!.add(range);
        if (range == 'bytes=0-0') {
          await _writeResponse(
            request.response,
            payload.sublist(0, 1),
            statusCode: HttpStatus.partialContent,
            contentRange: 'bytes 0-0/${payload.length}',
          );
          return;
        }

        final bounds = _rangeBounds(range);
        final end = failPartialResponse
            ? (bounds.start + 512 < bounds.end
                  ? bounds.start + 512
                  : bounds.end)
            : bounds.end;
        await _writeResponse(
          request.response,
          payload.sublist(bounds.start, end + 1),
          statusCode: HttpStatus.partialContent,
          contentRange: 'bytes ${bounds.start}-${bounds.end}/${payload.length}',
        );
      });
      addTearDown(() => server.close(force: true));
      const downloader = DioTransferDownloader(
        segmentConnections: 2,
        segmentSize: 2048,
        minimumSegmentedBytes: 1,
      );
      final url = 'http://${server.address.host}:${server.port}/file';

      await expectLater(
        downloader.download(
          dio: dio,
          url: url,
          partialPath: partialFile.path,
          expectedTotal: payload.length,
          cancelToken: CancelToken(),
          headers: const <String, String>{},
          receiveTimeout: const Duration(seconds: 5),
          onProgress: (_, _) {},
        ),
        throwsA(anything),
      );
      final metadata = File(
        DioTransferDownloader.metadataPathFor(partialFile.path),
      );
      expect(await metadata.exists(), isTrue);

      failPartialResponse = false;
      final result = await downloader.download(
        dio: dio,
        url: url,
        partialPath: partialFile.path,
        expectedTotal: payload.length,
        cancelToken: CancelToken(),
        headers: const <String, String>{},
        receiveTimeout: const Duration(seconds: 5),
        onProgress: (_, _) {},
      );

      final resumedFirst = ranges[2]!.firstWhere(
        (range) => range.endsWith('-2047'),
      );
      expect(_rangeBounds(resumedFirst).start, greaterThan(0));
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isTrue);
    });

    test('should 在探测不支持 Range 时回退单流下载', () async {
      final payload = List<int>.generate(4096, (index) => index % 227);
      final ranges = <String?>[];
      final server = await _startServer((request) async {
        ranges.add(request.headers.value('range'));
        await _writeResponse(request.response, payload);
      });
      addTearDown(() => server.close(force: true));

      final result =
          await const DioTransferDownloader(
            segmentConnections: 2,
            segmentSize: 2048,
            minimumSegmentedBytes: 1,
          ).download(
            dio: dio,
            url: 'http://${server.address.host}:${server.port}/file',
            partialPath: partialFile.path,
            expectedTotal: payload.length,
            cancelToken: CancelToken(),
            headers: const <String, String>{},
            receiveTimeout: const Duration(seconds: 5),
            onProgress: (_, _) {},
          );

      expect(ranges, <String?>['bytes=0-0', null]);
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isFalse);
      expect(
        await File(DioTransferDownloader.metadataPathFor(partialFile.path))
            .exists(),
        isFalse,
      );
    });

    test('should 在分片请求不再返回 206 时回退单流下载', () async {
      final payload = List<int>.generate(4096, (index) => index % 211);
      final ranges = <String?>[];
      final server = await _startServer((request) async {
        final range = request.headers.value('range');
        ranges.add(range);
        if (range == 'bytes=0-0') {
          await _writeResponse(
            request.response,
            payload.sublist(0, 1),
            statusCode: HttpStatus.partialContent,
            contentRange: 'bytes 0-0/${payload.length}',
          );
          return;
        }
        await _writeResponse(request.response, payload);
      });
      addTearDown(() => server.close(force: true));

      final result =
          await const DioTransferDownloader(
            segmentConnections: 2,
            segmentSize: 4096,
            minimumSegmentedBytes: 1,
          ).download(
            dio: dio,
            url: 'http://${server.address.host}:${server.port}/file',
            partialPath: partialFile.path,
            expectedTotal: payload.length,
            cancelToken: CancelToken(),
            headers: const <String, String>{},
            receiveTimeout: const Duration(seconds: 5),
            onProgress: (_, _) {},
          );

      expect(ranges, <String?>['bytes=0-0', 'bytes=0-4095', null]);
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isFalse);
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

({int start, int end}) _rangeBounds(String range) {
  final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range);
  if (match == null) throw FormatException('无效 Range：$range');
  return (start: int.parse(match.group(1)!), end: int.parse(match.group(2)!));
}
