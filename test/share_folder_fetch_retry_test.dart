import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';

/// 按脚本依次返回响应体的假适配器（记录请求次数与参数）。
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.bodies);

  /// 第 N 次请求用第 N 个响应；用完后一直用最后一个。
  final List<String> bodies;
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(Map<String, dynamic>.from(options.data as Map));
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

ShareFolderPaging _paging() => ShareFolderPaging(
  base: 'https://example.com',
  referer: 'https://example.com/s/abc',
  fid: '123',
  lx: '2',
  t: '1700000000',
  k: 'abcdefghijklmnop',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LanzouClient.requestInterval = Duration.zero);
  tearDown(
    () => LanzouClient.requestInterval = const Duration(milliseconds: 300),
  );

  // 真机上「从收藏进分享文件夹、自动补下一页」时偶发失败、底部闪「重试」：
  // 抓到的错误是「获取分享文件列表失败」（服务端暂时给不出数据）。
  // 这类「稍后再试」应该在客户端内部消化掉，重试同一页。
  test('分享分页遇到服务端忙 / 解析失败会自动重试同一页', () async {
    final client = LanzouClient(uid: '0');
    final adapter = _ScriptedAdapter([
      '{"zt":4}', // 服务端要求稍后重试
      'not json', // 挑战页 / 空响应这类解析失败
      '{"zt":1,"text":[{'
          '"id":"iabc123","name_all":"a.zip","size":"1 M","time":"2024-01-01"'
          '}]}',
    ]);
    client.dio.httpClientAdapter = adapter;

    final result = await client.fetchShareFolderFiles(_paging(), 2);

    expect(adapter.requests.length, 3, reason: '前两次失败都要自动重试同一页');
    expect(adapter.requests.every((r) => '${r['pg']}' == '2'), isTrue);
    expect(result.files.single.name, 'a.zip');
    expect(result.hasMore, isTrue);
  });

  test('分享分页拿到 zt=2 表示已到底', () async {
    final client = LanzouClient(uid: '0');
    final adapter = _ScriptedAdapter(['{"zt":2}']);
    client.dio.httpClientAdapter = adapter;

    final result = await client.fetchShareFolderFiles(_paging(), 2);

    expect(adapter.requests.length, 1);
    expect(result.files, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('服务端给了明确错误信息时立即报错，不做无谓重试', () async {
    final client = LanzouClient(uid: '0');
    final adapter = _ScriptedAdapter(['{"zt":0,"info":"文件不存在"}']);
    client.dio.httpClientAdapter = adapter;

    await expectLater(
      client.fetchShareFolderFiles(_paging(), 2),
      throwsA(
        isA<LanzouException>().having((e) => e.message, 'message', '文件不存在'),
      ),
    );
    expect(adapter.requests.length, 1);
  });

  // 真机上抓到的就是这条：服务端回「请刷新，重试N」，
  // 要求客户端把 N 填回 rep 参数再请求一次。
  test('「请刷新，重试N」会按服务端给的 rep 重试', () async {
    final client = LanzouClient(uid: '0');
    final adapter = _ScriptedAdapter(['{"zt":0,"info":"请刷新，重试1"}', '{"zt":2}']);
    client.dio.httpClientAdapter = adapter;

    final result = await client.fetchShareFolderFiles(_paging(), 2);

    expect(adapter.requests.length, 2);
    expect(adapter.requests.first['rep'], '0');
    expect(adapter.requests.last['rep'], '1', reason: '要把服务端给的 N 填回 rep');
    expect(result.hasMore, isFalse);
  });
}
