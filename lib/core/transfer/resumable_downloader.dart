import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

typedef TransferDownloadProgress = void Function(int received, int total);

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
/// 服务端忽略 Range 并返回 200 时自动截断后从头写；返回了不匹配的 206
/// 时放弃该响应并重发一次完整请求。网络中断和用户暂停都不会删除半截文件。
class DioTransferDownloader implements TransferDownloader {
  const DioTransferDownloader();

  static final RegExp _contentRangePattern = RegExp(
    r'^bytes\s+(\d+)-(\d+)/(\d+)$',
    caseSensitive: false,
  );

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
      final range = _parseContentRange(response.headers.value('content-range'));
      var offset = existing;
      var total = expectedTotal;
      if (status == HttpStatus.partialContent) {
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
        if (responseLength > 0) total = responseLength;
      }

      final output = await file.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      var received = 0;
      try {
        await for (final chunk in body.stream) {
          if (cancelToken.isCancelled) {
            throw DioException.requestCancelled(
              requestOptions: response.requestOptions,
              reason: cancelToken.cancelError,
            );
          }
          await output.writeFrom(chunk);
          received += chunk.length;
          onProgress(offset + received, total);
        }
        await output.flush();
      } finally {
        await output.close();
      }

      final actualTotal = await file.length();
      if (total > 0 && actualTotal != total) {
        throw ResumableDownloadException('下载文件大小不一致：$actualTotal / $total');
      }
      return TransferDownloadResult(
        total: total > 0 ? total : actualTotal,
        resumed: offset > 0,
      );
    }
  }

  static int _contentLength(Headers headers) =>
      int.tryParse(headers.value('content-length') ?? '') ?? 0;

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

  static Future<void> _cancelStream(ResponseBody body) async {
    final subscription = body.stream.listen((_) {});
    await subscription.cancel();
  }
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
