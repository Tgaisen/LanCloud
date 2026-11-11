import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef TransferDownloadProgress = void Function(int received, int total);
typedef SegmentConnectionsProvider = int Function();

class TransferDownloadResult {
  const TransferDownloadResult({required this.total, required this.resumed});

  final int total;
  final bool resumed;
}

class ResumableDownloadException implements Exception {
  const ResumableDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 传输层可替换的下载能力：生产实现直接走 Dio，测试可注入假实现。
abstract interface class TransferDownloader {
  Future<TransferDownloadResult> download({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  });
}

/// 用 HTTP Range 在稳定 `.part` 文件上续传。
///
/// 默认使用单连接。配置多个 [segmentConnections] 且文件足够大时，会先探测
/// 服务端是否支持精确 Range，再通过多个请求下载固定分片。分片进度保存在
/// 稳定 `.part` 文件旁的 `.part.json` 中；服务端忽略 Range 或区间不匹配时，
/// 会清掉分片状态并回退到单连接下载。
class DioTransferDownloader implements TransferDownloader {
  const DioTransferDownloader({
    int segmentConnections = 1,
    this.segmentConnectionsProvider,
    this.transientRetryDelays = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    this.segmentSize = 8 * 1024 * 1024,
    this.minimumSegmentedBytes = 16 * 1024 * 1024,
  }) : assert(segmentConnections >= 1 && segmentConnections <= 4),
       _segmentConnections = segmentConnections,
       assert(segmentSize > 0),
       assert(minimumSegmentedBytes > 0);

  final int _segmentConnections;
  final SegmentConnectionsProvider? segmentConnectionsProvider;
  final List<Duration> transientRetryDelays;
  final int segmentSize;
  final int minimumSegmentedBytes;

  /// 每次下载开始时读取一次，设置变化只影响后续下载或恢复。
  int get segmentConnections {
    final configured =
        segmentConnectionsProvider?.call() ?? _segmentConnections;
    if (configured < 1) return 1;
    if (configured > 4) return 4;
    return configured;
  }

  static const int _maxSegments = 64;
  static const int _writeBatchBytes = 512 * 1024;
  static const int _checkpointBytes = 4 * 1024 * 1024;
  static const int _segmentAttempts = 2;

  static final RegExp _contentRangePattern = RegExp(
    r'^bytes\s+(\d+)-(\d+)/(\d+)$',
    caseSensitive: false,
  );

  /// 分片检查点路径。与 `.part` 同目录、同前缀，便于任务清理和恢复。
  static String metadataPathFor(String partialPath) => '$partialPath.json';

  /// 删除下载临时文件和分片检查点，供任务取消、删除及完成保存阶段调用。
  static Future<void> deleteState(String partialPath) async {
    for (final path in <String>[
      partialPath,
      metadataPathFor(partialPath),
      '${metadataPathFor(partialPath)}.tmp',
    ]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

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
    for (var retry = 0; ; retry++) {
      try {
        return await _downloadOnce(
          dio: dio,
          url: url,
          partialPath: partialPath,
          expectedTotal: expectedTotal,
          cancelToken: cancelToken,
          headers: headers,
          receiveTimeout: receiveTimeout,
          onProgress: onProgress,
        );
      } on Object catch (error, stackTrace) {
        final transient = switch (error) {
          DioException dioError => _isTransient(dioError),
          HttpException() || SocketException() => true,
          _ => false,
        };
        if (cancelToken.isCancelled ||
            retry >= transientRetryDelays.length ||
            !transient) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        final delay = transientRetryDelays[retry];
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (cancelToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: url),
            reason: cancelToken.cancelError,
          );
        }
      }
    }
  }

  Future<TransferDownloadResult> _downloadOnce({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    final metadataFile = File(metadataPathFor(partialPath));
    final hasSegmentedState = await metadataFile.exists();
    final connections = segmentConnections;
    if ((connections <= 1 && !hasSegmentedState) ||
        (!hasSegmentedState &&
            expectedTotal > 0 &&
            expectedTotal < minimumSegmentedBytes)) {
      if (hasSegmentedState) await deleteState(partialPath);
      return _downloadSequential(
        dio: dio,
        url: url,
        partialPath: partialPath,
        expectedTotal: expectedTotal,
        cancelToken: cancelToken,
        headers: headers,
        receiveTimeout: receiveTimeout,
        onProgress: onProgress,
      );
    }

    final probe = await _probeRange(
      dio: dio,
      url: url,
      cancelToken: cancelToken,
      headers: headers,
      receiveTimeout: receiveTimeout,
    );
    if (probe == null || probe.total < minimumSegmentedBytes) {
      if (hasSegmentedState) await deleteState(partialPath);
      return _downloadSequential(
        dio: dio,
        url: url,
        partialPath: partialPath,
        expectedTotal: expectedTotal,
        cancelToken: cancelToken,
        headers: headers,
        receiveTimeout: receiveTimeout,
        onProgress: onProgress,
      );
    }

    try {
      return await _downloadSegmented(
        dio: dio,
        url: url,
        partialPath: partialPath,
        probe: probe,
        cancelToken: cancelToken,
        headers: headers,
        receiveTimeout: receiveTimeout,
        connections: connections,
        onProgress: onProgress,
      );
    } on _RestartSequential {
      await deleteState(partialPath);
      return _downloadSequential(
        dio: dio,
        url: url,
        partialPath: partialPath,
        expectedTotal: probe.total,
        cancelToken: cancelToken,
        headers: headers,
        receiveTimeout: receiveTimeout,
        onProgress: onProgress,
      );
    }
  }

  Future<_RangeProbe?> _probeRange({
    required Dio dio,
    required String url,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
  }) async {
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: receiveTimeout,
        validateStatus: (status) =>
            status == HttpStatus.ok ||
            status == HttpStatus.partialContent ||
            status == HttpStatus.requestedRangeNotSatisfiable,
        headers: <String, dynamic>{
          ...headers,
          'Accept-Encoding': 'identity',
          'Range': 'bytes=0-0',
        },
      ),
    );
    final body = response.data;
    if (body == null) return null;
    await _cancelStream(body);

    // gzip 是压缩表示，Range 与 Content-Range 都按压缩字节计算，不能用于
    // 恢复解压后的本地文件。
    if (_isTransparentlyDecodedGzip(response.headers)) return null;
    if (response.statusCode != HttpStatus.partialContent) return null;
    final range = _parseContentRange(response.headers.value('content-range'));
    if (range == null ||
        range.start != 0 ||
        range.end != 0 ||
        range.total <= 0) {
      return null;
    }
    return _RangeProbe(
      total: range.total,
      etag: _headerValue(response.headers, 'etag'),
      lastModified: _headerValue(response.headers, 'last-modified'),
    );
  }

  Future<TransferDownloadResult> _downloadSegmented({
    required Dio dio,
    required String url,
    required String partialPath,
    required _RangeProbe probe,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required int connections,
    required TransferDownloadProgress onProgress,
  }) async {
    final file = File(partialPath);
    await file.parent.create(recursive: true);
    final metadataFile = File(metadataPathFor(partialPath));
    final stored = await _readManifest(metadataFile);
    final length = await file.exists() ? await file.length() : 0;
    var manifest = stored;
    final canResume =
        manifest != null &&
        manifest.total == probe.total &&
        manifest.matches(probe) &&
        length == manifest.total;

    if (!canResume) {
      if (stored == null && !await metadataFile.exists()) {
        if (length == probe.total) {
          onProgress(length, probe.total);
          return TransferDownloadResult(total: probe.total, resumed: true);
        }
      }
      manifest = _SegmentManifest.create(
        total: probe.total,
        segmentSize: _segmentSizeFor(probe.total),
        etag: probe.etag,
        lastModified: probe.lastModified,
      );
      await _writeManifest(metadataFile, manifest);
      final output = await file.open(mode: FileMode.append);
      try {
        await output.truncate(manifest.total);
        await output.flush();
      } finally {
        await output.close();
      }
    }

    final resumed = manifest.received > 0;
    final writer = await _SegmentWriter.open(
      file: file,
      metadataFile: metadataFile,
      manifest: manifest,
      onProgress: onProgress,
    );
    var closed = false;
    try {
      if (!manifest.isComplete) {
        await _downloadSegments(
          dio: dio,
          url: url,
          probe: probe,
          cancelToken: cancelToken,
          headers: headers,
          receiveTimeout: receiveTimeout,
          connections: connections,
          manifest: manifest,
          writer: writer,
        );
      }
      await writer.checkpoint(force: true);
      if (!manifest.isComplete) {
        throw ResumableDownloadException(
          '分片下载未完成：${manifest.received} / ${manifest.total}',
        );
      }
      await writer.close();
      closed = true;
      onProgress(manifest.total, manifest.total);
      return TransferDownloadResult(total: manifest.total, resumed: resumed);
    } finally {
      if (!closed) await writer.close();
    }
  }

  Future<void> _downloadSegments({
    required Dio dio,
    required String url,
    required _RangeProbe probe,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required int connections,
    required _SegmentManifest manifest,
    required _SegmentWriter writer,
  }) async {
    final linked = _LinkedCancelToken(cancelToken);
    var nextIndex = 0;
    Object? firstError;
    StackTrace? firstStack;

    Future<void> worker() async {
      try {
        while (!linked.token.isCancelled) {
          if (nextIndex >= manifest.segments.length) return;
          final segment = manifest.segments[nextIndex];
          nextIndex += 1;
          if (segment.isComplete) continue;
          await _downloadSegmentWithRetry(
            dio: dio,
            url: url,
            probe: probe,
            cancelToken: linked.token,
            headers: headers,
            receiveTimeout: receiveTimeout,
            segment: segment,
            writer: writer,
          );
        }
      } catch (error, stackTrace) {
        if (firstError == null) {
          firstError = error;
          firstStack = stackTrace;
          linked.cancel(error);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    try {
      await Future.wait(<Future<void>>[
        for (var i = 0; i < connections; i++) worker(),
      ]);
    } catch (_) {}

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.empty);
    }
    if (cancelToken.isCancelled) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: url),
        reason: cancelToken.cancelError,
      );
    }
  }

  Future<void> _downloadSegmentWithRetry({
    required Dio dio,
    required String url,
    required _RangeProbe probe,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required _Segment segment,
    required _SegmentWriter writer,
  }) async {
    for (var attempt = 1; attempt <= _segmentAttempts; attempt++) {
      try {
        await _downloadSegment(
          dio: dio,
          url: url,
          probe: probe,
          cancelToken: cancelToken,
          headers: headers,
          receiveTimeout: receiveTimeout,
          segment: segment,
          writer: writer,
        );
        return;
      } on DioException catch (error) {
        if (cancelToken.isCancelled ||
            !_isTransient(error) ||
            attempt == _segmentAttempts) {
          rethrow;
        }
      } on _IncompleteSegment {
        if (attempt == _segmentAttempts) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
    }
  }

  Future<void> _downloadSegment({
    required Dio dio,
    required String url,
    required _RangeProbe probe,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required _Segment segment,
    required _SegmentWriter writer,
  }) async {
    final remaining = segment.remaining;
    if (remaining <= 0) return;
    final start = segment.end - remaining + 1;
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: receiveTimeout,
        validateStatus: (status) =>
            status == HttpStatus.ok ||
            status == HttpStatus.partialContent ||
            status == HttpStatus.requestedRangeNotSatisfiable,
        headers: <String, dynamic>{
          ...headers,
          'Accept-Encoding': 'identity',
          'Range': 'bytes=$start-${segment.end}',
        },
      ),
    );
    final body = response.data;
    if (body == null) {
      throw ResumableDownloadException(
        '下载响应没有内容（HTTP ${response.statusCode ?? 0}）',
      );
    }
    if (response.statusCode != HttpStatus.partialContent) {
      await _cancelStream(body);
      throw const _RestartSequential();
    }
    if (_isTransparentlyDecodedGzip(response.headers)) {
      await _cancelStream(body);
      throw const _RestartSequential();
    }
    final range = _parseContentRange(response.headers.value('content-range'));
    if (range == null ||
        range.start != start ||
        range.end != segment.end ||
        range.total != probe.total ||
        !_sameHeaderValue(probe.etag, _headerValue(response.headers, 'etag')) ||
        !_sameHeaderValue(
          probe.lastModified,
          _headerValue(response.headers, 'last-modified'),
        )) {
      await _cancelStream(body);
      throw const _RestartSequential();
    }

    var received = 0;
    var written = 0;
    final expectedLength = remaining;
    final pending = BytesBuilder(copy: false);

    Future<void> flushPending() async {
      if (pending.length == 0) return;
      final bytes = pending.takeBytes();
      await writer.write(
        segment: segment,
        offset: start + written,
        bytes: bytes,
      );
      written += bytes.length;
    }

    try {
      await for (final chunk in body.stream) {
        if (cancelToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: response.requestOptions,
            reason: cancelToken.cancelError,
          );
        }
        if (received + chunk.length > expectedLength) {
          throw const _RestartSequential();
        }
        pending.add(chunk);
        received += chunk.length;
        if (pending.length >= _writeBatchBytes) {
          await flushPending();
        }
      }
    } finally {
      await flushPending();
    }
    if (received != expectedLength || written != expectedLength) {
      throw const _IncompleteSegment();
    }
  }

  Future<TransferDownloadResult> _downloadSequential({
    required Dio dio,
    required String url,
    required String partialPath,
    required int expectedTotal,
    required CancelToken cancelToken,
    required Map<String, String> headers,
    required Duration receiveTimeout,
    required TransferDownloadProgress onProgress,
  }) async {
    final file = File(partialPath);
    await file.parent.create(recursive: true);
    var existing = await file.exists() ? await file.length() : 0;
    if (expectedTotal > 0 && existing == expectedTotal) {
      onProgress(existing, expectedTotal);
      return TransferDownloadResult(total: expectedTotal, resumed: true);
    }
    if (expectedTotal > 0 && existing > expectedTotal) {
      await file.delete();
      existing = 0;
    }

    var retriedWithoutRange = false;
    while (true) {
      final resuming = existing > 0;
      final response = await dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: receiveTimeout,
          validateStatus: (status) =>
              status == HttpStatus.ok ||
              status == HttpStatus.partialContent ||
              status == HttpStatus.requestedRangeNotSatisfiable,
          headers: <String, dynamic>{
            ...headers,
            'Accept-Encoding': 'identity',
            if (resuming) 'Range': 'bytes=$existing-',
          },
        ),
      );
      final body = response.data;
      if (body == null) {
        throw ResumableDownloadException(
          '下载响应没有内容（HTTP ${response.statusCode ?? 0}）',
        );
      }

      final status = response.statusCode;
      if (status == HttpStatus.requestedRangeNotSatisfiable) {
        await _cancelStream(body);
        final length = await file.exists() ? await file.length() : 0;
        if (expectedTotal > 0 && length == expectedTotal) {
          onProgress(length, expectedTotal);
          return TransferDownloadResult(total: expectedTotal, resumed: true);
        }
        if (retriedWithoutRange) {
          throw const ResumableDownloadException('服务器拒绝了断点续传请求');
        }
        retriedWithoutRange = true;
        if (await file.exists()) await file.delete();
        existing = 0;
        continue;
      }

      if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
        await _cancelStream(body);
        throw DioException.badResponse(
          statusCode: status ?? 0,
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final responseLength = _contentLength(response.headers);
      final gzipEncoded = _isTransparentlyDecodedGzip(response.headers);
      final range = _parseContentRange(response.headers.value('content-range'));
      var offset = existing;
      var total = expectedTotal;
      if (status == HttpStatus.partialContent) {
        if (gzipEncoded) {
          await _cancelStream(body);
          if (retriedWithoutRange) {
            throw const ResumableDownloadException('服务器对压缩内容返回了断点范围');
          }
          retriedWithoutRange = true;
          await deleteState(partialPath);
          existing = 0;
          continue;
        }
        if (range == null ||
            range.start != existing ||
            (expectedTotal > 0 && range.total != expectedTotal)) {
          await _cancelStream(body);
          if (retriedWithoutRange) {
            throw const ResumableDownloadException('服务器返回的断点范围无效');
          }
          retriedWithoutRange = true;
          if (await file.exists()) await file.delete();
          existing = 0;
          continue;
        }
        offset = existing;
        total = range.total;
      } else {
        // 200 表示服务器没有采用 Range，响应体是完整文件，必须从头覆盖。
        offset = 0;
        if (!gzipEncoded && responseLength > 0) total = responseLength;
      }

      final output = await file.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      var written = 0;
      final pending = BytesBuilder(copy: false);

      Future<void> flushPending() async {
        if (pending.length == 0) return;
        final bytes = pending.takeBytes();
        await output.writeFrom(bytes);
        written += bytes.length;
        onProgress(offset + written, total);
      }

      try {
        await for (final chunk in body.stream) {
          if (cancelToken.isCancelled) {
            throw DioException.requestCancelled(
              requestOptions: response.requestOptions,
              reason: cancelToken.cancelError,
            );
          }
          pending.add(chunk);
          if (pending.length >= _writeBatchBytes) {
            await flushPending();
          }
        }
      } finally {
        try {
          await flushPending();
        } finally {
          try {
            await output.flush();
          } finally {
            await output.close();
          }
        }
      }

      final actualTotal = await file.length();
      if (!gzipEncoded && total > 0 && actualTotal != total) {
        throw ResumableDownloadException('下载文件大小不一致：$actualTotal / $total');
      }
      if (gzipEncoded) {
        // HttpClient 默认会透明解压 gzip 正文，但保留压缩表示的
        // Content-Length。此时落盘字节数才是解压后的真实总大小。
        onProgress(actualTotal, actualTotal);
      }
      return TransferDownloadResult(
        total: gzipEncoded || total <= 0 ? actualTotal : total,
        resumed: offset > 0,
      );
    }
  }

  int _segmentSizeFor(int total) {
    final minimumForCap = (total + _maxSegments - 1) ~/ _maxSegments;
    return minimumForCap > segmentSize ? minimumForCap : segmentSize;
  }

  static Future<_SegmentManifest?> _readManifest(File file) async {
    try {
      if (!await file.exists()) return null;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      if (_asInt(decoded['version']) != 1) return null;
      final total = _asInt(decoded['total']);
      final segmentSize = _asInt(decoded['segment_size']);
      final rawSegments = decoded['segments'];
      if (total == null ||
          total <= 0 ||
          segmentSize == null ||
          segmentSize <= 0 ||
          rawSegments is! List<Object?>) {
        return null;
      }
      var expectedStart = 0;
      final segments = <_Segment>[];
      for (final raw in rawSegments) {
        if (raw is! Map<String, Object?>) return null;
        final start = _asInt(raw['start']);
        final end = _asInt(raw['end']);
        final committed = _asInt(raw['committed']);
        if (start == null ||
            end == null ||
            committed == null ||
            start != expectedStart ||
            end < start ||
            end >= total ||
            committed < 0 ||
            committed > end - start + 1) {
          return null;
        }
        segments.add(_Segment(start: start, end: end, committed: committed));
        expectedStart = end + 1;
      }
      if (expectedStart != total) return null;
      return _SegmentManifest(
        total: total,
        segmentSize: segmentSize,
        etag: _asString(decoded['etag']),
        lastModified: _asString(decoded['last_modified']),
        segments: segments,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeManifest(
    File file,
    _SegmentManifest manifest,
  ) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'total': manifest.total,
        'segment_size': manifest.segmentSize,
        'etag': manifest.etag,
        'last_modified': manifest.lastModified,
        'segments': <Map<String, Object?>>[
          for (final segment in manifest.segments)
            <String, Object?>{
              'start': segment.start,
              'end': segment.end,
              'committed': segment.committed,
            },
        ],
      }),
      flush: true,
    );
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }

  static int _contentLength(Headers headers) =>
      int.tryParse(headers.value('content-length') ?? '') ?? 0;

  /// Dart HttpClient 只会在 Content-Encoding 恰好为 gzip 时透明解压响应体，
  /// 且不会同步改写 Content-Length。返回值必须准确对应这一行为。
  static bool _isTransparentlyDecodedGzip(Headers headers) =>
      headers.value(HttpHeaders.contentEncodingHeader)?.trim().toLowerCase() ==
      'gzip';

  static String? _headerValue(Headers headers, String name) {
    final value = headers.value(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static bool _sameHeaderValue(String? expected, String? actual) =>
      expected == null || actual == null || expected == actual;

  static int? _asInt(Object? value) => value is int ? value : null;

  static String _asString(Object? value) => value is String ? value : '';

  static _ContentRange? _parseContentRange(String? value) {
    if (value == null) return null;
    final match = _contentRangePattern.firstMatch(value.trim());
    if (match == null) return null;
    final start = int.tryParse(match.group(1) ?? '');
    final end = int.tryParse(match.group(2) ?? '');
    final total = int.tryParse(match.group(3) ?? '');
    if (start == null || end == null || total == null) return null;
    if (start < 0 || end < start || total <= end) return null;
    return _ContentRange(start: start, end: end, total: total);
  }

  static bool _isTransient(DioException error) {
    if (error.type
        case DioExceptionType.connectionTimeout ||
            DioExceptionType.sendTimeout ||
            DioExceptionType.receiveTimeout ||
            DioExceptionType.connectionError ||
            DioExceptionType.unknown) {
      return true;
    }
    return switch (error.response?.statusCode) {
      HttpStatus.requestTimeout ||
      HttpStatus.internalServerError ||
      HttpStatus.badGateway ||
      HttpStatus.serviceUnavailable ||
      HttpStatus.gatewayTimeout => true,
      _ => false,
    };
  }

  static Future<void> _cancelStream(ResponseBody body) async {
    final subscription = body.stream.listen((_) {});
    await subscription.cancel();
  }
}

class _RangeProbe {
  const _RangeProbe({
    required this.total,
    required this.etag,
    required this.lastModified,
  });

  final int total;
  final String? etag;
  final String? lastModified;
}

class _SegmentManifest {
  _SegmentManifest({
    required this.total,
    required this.segmentSize,
    required this.etag,
    required this.lastModified,
    required this.segments,
  });

  factory _SegmentManifest.create({
    required int total,
    required int segmentSize,
    required String? etag,
    required String? lastModified,
  }) {
    final segments = <_Segment>[];
    for (var start = 0; start < total; start += segmentSize) {
      final end = start + segmentSize - 1 < total
          ? start + segmentSize - 1
          : total - 1;
      segments.add(_Segment(start: start, end: end, committed: 0));
    }
    return _SegmentManifest(
      total: total,
      segmentSize: segmentSize,
      etag: etag ?? '',
      lastModified: lastModified ?? '',
      segments: segments,
    );
  }

  final int total;
  final int segmentSize;
  final String etag;
  final String lastModified;
  final List<_Segment> segments;

  int get received =>
      segments.fold<int>(0, (sum, segment) => sum + segment.committed);

  bool get isComplete => received == total;

  bool matches(_RangeProbe probe) =>
      (etag.isEmpty || probe.etag == null || etag == probe.etag) &&
      (lastModified.isEmpty ||
          probe.lastModified == null ||
          lastModified == probe.lastModified);
}

class _Segment {
  _Segment({required this.start, required this.end, required this.committed});

  final int start;
  final int end;
  int committed;

  int get length => end - start + 1;
  int get remaining => length - committed;
  bool get isComplete => committed == length;
}

class _SegmentWriter {
  _SegmentWriter._({
    required this._output,
    required this.metadataFile,
    required this.manifest,
    required this.onProgress,
  });

  static Future<_SegmentWriter> open({
    required File file,
    required File metadataFile,
    required _SegmentManifest manifest,
    required TransferDownloadProgress onProgress,
  }) async {
    final writer = _SegmentWriter._(
      output: await file.open(mode: FileMode.append),
      metadataFile: metadataFile,
      manifest: manifest,
      onProgress: onProgress,
    );
    writer.onProgress(manifest.received, manifest.total);
    return writer;
  }

  final RandomAccessFile _output;
  final File metadataFile;
  final _SegmentManifest manifest;
  final TransferDownloadProgress onProgress;

  Future<void> _tail = Future<void>.value();
  int _uncheckpointed = 0;
  bool _closed = false;

  Future<void> write({
    required _Segment segment,
    required int offset,
    required List<int> bytes,
  }) {
    if (bytes.isEmpty) return Future<void>.value();
    return _enqueue(() async {
      await _output.setPosition(offset);
      await _output.writeFrom(bytes);
      segment.committed += bytes.length;
      _uncheckpointed += bytes.length;
      if (segment.isComplete ||
          _uncheckpointed >= DioTransferDownloader._checkpointBytes) {
        await _checkpoint();
      }
      onProgress(manifest.received, manifest.total);
    });
  }

  Future<void> checkpoint({bool force = false}) => _enqueue(() async {
    if (force || _uncheckpointed > 0) await _checkpoint();
  });

  Future<void> close() {
    if (_closed) return _tail;
    return _enqueue(() async {
      try {
        await _checkpoint();
      } finally {
        _closed = true;
        await _output.close();
      }
    });
  }

  Future<void> _checkpoint() async {
    await _output.flush();
    await DioTransferDownloader._writeManifest(metadataFile, manifest);
    _uncheckpointed = 0;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        await action();
        result.complete();
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

class _LinkedCancelToken {
  _LinkedCancelToken(this.parent) {
    parent.whenCancel.then((error) {
      if (!token.isCancelled) token.cancel(error);
    });
  }

  final CancelToken parent;
  final CancelToken token = CancelToken();

  void cancel(Object error) {
    if (!parent.isCancelled && !token.isCancelled) token.cancel(error);
  }
}

class _RestartSequential implements Exception {
  const _RestartSequential();
}

class _IncompleteSegment implements Exception {
  const _IncompleteSegment();
}

class _ContentRange {
  const _ContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;
}
