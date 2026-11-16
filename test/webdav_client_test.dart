import 'dart:typed_data';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/webdav_client.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await requestStream?.drain<void>();
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _HangingAdapter implements HttpClientAdapter {
  final Completer<ResponseBody> response = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => response.future;

  @override
  void close({bool force = false}) {}
}

void main() {
  test('上传与删除分别使用 PUT / DELETE，并保留目标路径', () async {
    final dio = Dio();
    final adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;
    final client = WebdavClient(
      url: 'https://dav.example.com/backup/',
      dio: dio,
    );

    await client.upload('lancloud.json', '{}');
    await client.delete('lancloud.json');

    expect(adapter.requests.map((request) => request.method), [
      'PUT',
      'DELETE',
    ]);
    expect(adapter.requests.map((request) => request.uri.toString()), [
      'https://dav.example.com/backup/lancloud.json',
      'https://dav.example.com/backup/lancloud.json',
    ]);
  });

  test('下载取消后保留 Dio 取消类型，不转换成普通网络错误', () async {
    final dio = Dio();
    dio.httpClientAdapter = _HangingAdapter();
    final client = WebdavClient(
      url: 'https://dav.example.com/backup/',
      dio: dio,
    );
    final cancelToken = CancelToken();

    final pending = client.download('lancloud.json', cancelToken: cancelToken);
    await Future<void>.delayed(Duration.zero);
    cancelToken.cancel('用户取消');

    await expectLater(
      pending,
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });
}
