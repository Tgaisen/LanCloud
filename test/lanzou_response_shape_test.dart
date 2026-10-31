import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.bodies);

  final List<String> bodies;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await requestStream?.drain<void>();
    final body = bodies[(requests.length - 1).clamp(0, bodies.length - 1)];
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({LanzouClient client, _ScriptedAdapter adapter}) _clientWith(
  List<String> bodies,
) {
  final adapter = _ScriptedAdapter(bodies);
  final client = LanzouClient(uid: '0')..dio.httpClientAdapter = adapter;
  return (client: client, adapter: adapter);
}

Matcher _throwsLanzouError(LanzouErrorCode code) =>
    throwsA(isA<LanzouException>().having((error) => error.code, 'code', code));

const _malformedInfoValues = <Object?>['not-a-map', <Object?>[]];

void main() {
  setUp(() => LanzouClient.requestInterval = Duration.zero);
  tearDown(
    () => LanzouClient.requestInterval = const Duration(milliseconds: 300),
  );

  for (final malformed in _malformedInfoValues) {
    final shape = malformed is List ? '列表' : '字符串';

    test('文件分享 info 为$shape时返回结构化错误', () async {
      final setup = _clientWith([
        jsonEncode({'info': malformed}),
      ]);

      await expectLater(
        setup.client.shareInfoOfFile('file-id'),
        _throwsLanzouError(LanzouErrorCode.fileShareInfoFailed),
      );
      expect(setup.adapter.requests.length, 1);
    });

    test('文件夹分享 info 为$shape时返回结构化错误', () async {
      final setup = _clientWith([
        jsonEncode({'zt': 1, 'info': malformed}),
      ]);

      await expectLater(
        setup.client.shareInfoOfFolder('folder-id'),
        _throwsLanzouError(LanzouErrorCode.folderShareInfoFailed),
      );
      expect(setup.adapter.requests.length, 1);
    });

    test('读取文件夹描述时 info 为$shape不会继续写回', () async {
      final setup = _clientWith([
        jsonEncode({'info': malformed}),
      ]);

      await expectLater(
        setup.client.setFolderDesc('folder-id', '新描述'),
        _throwsLanzouError(LanzouErrorCode.readFolderInfoFailed),
      );
      expect(
        setup.adapter.requests.length,
        1,
        reason: '读取失败后不应继续发送 task 4 保存请求',
      );
    });
  }

  test('合法 info 对象仍可解析文件分享信息', () async {
    final setup = _clientWith([
      jsonEncode({
        'info': {
          'is_newd': 'https://pan.lanzouo.com',
          'f_id': 'iabc123',
          'onof': 1,
          'pwd': 'secret',
          'name': 'fallback.zip',
        },
      }),
      jsonEncode({'text': 'archive.zip', 'info': '说明'}),
    ]);

    final info = await setup.client.shareInfoOfFile('file-id');

    expect(info.url, 'https://pan.lanzouo.com/iabc123');
    expect(info.pwd, 'secret');
    expect(info.name, 'archive.zip');
    expect(info.desc, '说明');
  });
}
