import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';

/// 记录请求地址的假适配器（返回空响应，调用方自己会兜底）。
class _UrlAdapter implements HttpClientAdapter {
  final List<Uri> uris = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uris.add(options.uri);
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LanzouClient.requestInterval = Duration.zero);
  tearDown(() {
    LanzouClient.requestInterval = const Duration(milliseconds: 300);
    // 恢复默认域名，别影响其它测试
    LanzouClient.apiBase = 'https://pc.woozooo.com';
    LanzouClient.uploadBase = 'https://up.woozooo.com';
  });

  test('接口域名跟随设置：网页版 / 网页登录地址都用当前配置的域名', () {
    LanzouClient.apiBase = 'https://up.woozooo.com';
    expect(LanzouClient.mydiskUrl, 'https://up.woozooo.com/mydisk.php');
    expect(LanzouClient.loginUrl, 'https://up.woozooo.com/account.php');

    LanzouClient.apiBase = 'https://pc.woozooo.com';
    expect(LanzouClient.mydiskUrl, 'https://pc.woozooo.com/mydisk.php');
    expect(LanzouClient.loginUrl, 'https://pc.woozooo.com/account.php');
  });

  test('网页版抓取跟随设置：个人中心 / 文件夹统计 / 默认 Referer', () async {
    // 两个域名都过一遍：写死其中一个的实现会在另一档上暴露出来
    for (final host in ['pc', 'up']) {
      LanzouClient.apiBase = 'https://$host.woozooo.com';
      LanzouClient.uploadBase = 'https://$host.woozooo.com';

      final client = LanzouClient(uid: '1');
      // 默认 Referer 按构造时的域名生成
      expect(
        client.dio.options.headers['Referer'],
        'https://$host.woozooo.com/mydisk.php',
      );

      final adapter = _UrlAdapter();
      client.dio.httpClientAdapter = adapter;

      await client.fetchAccountInfo();
      await client.folderStats('f1');

      expect(adapter.uris.length, 2);
      // 昵称 / 等级截取、文件夹统计都走当前配置的域名
      expect(adapter.uris[0].host, '$host.woozooo.com');
      expect(adapter.uris[0].path, '/myfile.php');
      expect(adapter.uris[0].queryParameters['item'], '1');
      expect(adapter.uris[1].host, '$host.woozooo.com');
      expect(adapter.uris[1].queryParameters['folder_id'], 'f1');
    }
  });
}
