import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
      final payload = List<int>.generate(1024 * 1024, (index) => index % 251);
      final requestedRange = Completer<String?>();
      final server = await _startServer((request) async {
        requestedRange.complete(request.headers.value('range'));
        await _writeResponse(request.response, payload, chunkSize: 16 * 1024);
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
      expect(progress.length, lessThan(5));
    });

    test('should 下载重定向后的 gzip 文本且不把压缩长度当作文件大小', () async {
      final payload = utf8.encode(
        List<String>.generate(512, (index) => '第$index行：蓝奏云文本下载。').join('\n'),
      );
      final server = await _startServer((request) async {
        if (request.uri.path == '/redirect') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/file.txt');
          await request.response.close();
          return;
        }
        await _writeGzipResponse(request.response, payload);
      });
      addTearDown(() => server.close(force: true));
      final progress = <(int, int)>[];

      final result = await const DioTransferDownloader().download(
        dio: dio,
        url: 'http://${server.address.host}:${server.port}/redirect',
        partialPath: partialFile.path,
        expectedTotal: 0,
        cancelToken: CancelToken(),
        headers: const <String, String>{},
        receiveTimeout: const Duration(seconds: 5),
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isFalse);
      expect(progress.last, (payload.length, payload.length));
    });

    test('should 在 gzip 的 206 响应后无 Range 重新请求完整文件', () async {
      final payload = utf8.encode(
        List<String>.generate(1024, (index) => 'gzip range $index').join('\n'),
      );
      final compressed = gzip.encode(payload);
      final initialLength = 16;
      await partialFile.writeAsBytes(payload.sublist(0, initialLength));
      final ranges = <String?>[];
      final server = await _startServer((request) async {
        final range = request.headers.value('range');
        ranges.add(range);
        if (range == null) {
          await _writeGzipResponse(request.response, payload);
          return;
        }
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.contentType = ContentType.text;
        request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $initialLength-${compressed.length - 1}/${compressed.length}',
        );
        request.response.contentLength = compressed.length;
        request.response.add(compressed);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final result = await const DioTransferDownloader().download(
        dio: dio,
        url: 'http://${server.address.host}:${server.port}/file.txt',
        partialPath: partialFile.path,
        expectedTotal: 0,
        cancelToken: CancelToken(),
        headers: const <String, String>{},
        receiveTimeout: const Duration(seconds: 5),
        onProgress: (_, _) {},
      );

      expect(ranges, <String?>['bytes=$initialLength-', null]);
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isFalse);
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

    test('should 在连接中途关闭后自动从断点重试', () async {
      final payload = List<int>.generate(32 * 1024, (index) => index % 217);
      final firstPart = 4096;
      final adapter = _InterruptedDownloadAdapter(
        payload: payload,
        firstPart: firstPart,
      );
      dio.httpClientAdapter = adapter;

      final result =
          await const DioTransferDownloader(
            transientRetryDelays: <Duration>[Duration.zero],
          ).download(
            dio: dio,
            url: 'https://cdn.example/file',
            partialPath: partialFile.path,
            expectedTotal: payload.length,
            cancelToken: CancelToken(),
            headers: const <String, String>{},
            receiveTimeout: const Duration(seconds: 5),
            onProgress: (_, _) {},
          );

      expect(adapter.ranges, <String?>[null, 'bytes=$firstPart-']);
      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(result.resumed, isTrue);
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
      final result =
          await const DioTransferDownloader(
            segmentConnections: 1,
            segmentSize: 2048,
            minimumSegmentedBytes: 1,
          ).download(
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

    test('should 每次下载开始时读取最新的连接数配置', () {
      var configured = 3;
      final downloader = DioTransferDownloader(
        segmentConnectionsProvider: () => configured,
      );

      expect(downloader.segmentConnections, 3);
      configured = 0;
      expect(downloader.segmentConnections, 1);
      configured = 9;
      expect(downloader.segmentConnections, 4);
    });

    test('should 将分片网络小块批量写入磁盘', () async {
      final payload = List<int>.generate(512 * 1024, (index) => index % 239);
      final server = await _startServer((request) async {
        final range = request.headers.value('range');
        if (range == null) fail('分片请求必须带 Range');
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
        await _writeResponse(
          request.response,
          payload.sublist(bounds.start, bounds.end + 1),
          statusCode: HttpStatus.partialContent,
          contentRange: 'bytes ${bounds.start}-${bounds.end}/${payload.length}',
          chunkSize: 16 * 1024,
        );
      });
      addTearDown(() => server.close(force: true));
      final progress = <int>[];

      final result =
          await const DioTransferDownloader(
            segmentConnections: 2,
            segmentSize: 256 * 1024,
            minimumSegmentedBytes: 1,
          ).download(
            dio: dio,
            url: 'http://${server.address.host}:${server.port}/file',
            partialPath: partialFile.path,
            expectedTotal: payload.length,
            cancelToken: CancelToken(),
            headers: const <String, String>{},
            receiveTimeout: const Duration(seconds: 5),
            onProgress: (received, _) => progress.add(received),
          );

      expect(await partialFile.readAsBytes(), payload);
      expect(result.total, payload.length);
      expect(progress.length, lessThanOrEqualTo(6));
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
  int? chunkSize,
}) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.binary;
  response.contentLength = payload.length;
  if (contentRange != null) {
    response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
  }
  if (chunkSize == null) {
    response.add(payload);
  } else {
    for (var start = 0; start < payload.length; start += chunkSize) {
      final end = start + chunkSize < payload.length
          ? start + chunkSize
          : payload.length;
      response.add(payload.sublist(start, end));
      await response.flush();
    }
  }
  await response.close();
}

Future<void> _writeGzipResponse(
  HttpResponse response,
  List<int> payload,
) async {
  final compressed = gzip.encode(payload);
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType.text;
  response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
  response.contentLength = compressed.length;
  response.add(compressed);
  await response.close();
}

({int start, int end}) _rangeBounds(String range) {
  final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range);
  if (match == null) throw FormatException('无效 Range：$range');
  return (start: int.parse(match.group(1)!), end: int.parse(match.group(2)!));
}

class _InterruptedDownloadAdapter implements HttpClientAdapter {
  _InterruptedDownloadAdapter({required this.payload, required this.firstPart});

  final List<int> payload;
  final int firstPart;
  final List<String?> ranges = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final range = options.headers['Range'] as String?;
    ranges.add(range);
    if (range == null) {
      return ResponseBody(
        _interruptedBody(),
        HttpStatus.ok,
        headers: <String, List<String>>{
          Headers.contentLengthHeader: <String>['${payload.length}'],
          Headers.contentTypeHeader: <String>['application/octet-stream'],
        },
      );
    }

    final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range);
    final start = int.parse(match!.group(1)!);
    return ResponseBody(
      Stream<Uint8List>.value(Uint8List.fromList(payload.sublist(start))),
      HttpStatus.partialContent,
      headers: <String, List<String>>{
        Headers.contentLengthHeader: <String>['${payload.length - start}'],
        HttpHeaders.contentRangeHeader: <String>[
          'bytes $start-${payload.length - 1}/${payload.length}',
        ],
        Headers.contentTypeHeader: <String>['application/octet-stream'],
      },
    );
  }

  Stream<Uint8List> _interruptedBody() async* {
    yield Uint8List.fromList(payload.sublist(0, firstPart));
    throw const HttpException('Connection closed while receiving data');
  }

  @override
  void close({bool force = false}) {}
}
