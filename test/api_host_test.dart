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
    LanzouClient.uploadPath = 'html5up.php';
  });

  test('接口域名跟随设置：网页版 / 网页登录地址都用当前配置的域名', () {
    LanzouClient.apiBase = 'https://up.woozooo.com';
    expect(LanzouClient.mydiskUrl, 'https://up.woozooo.com/mydisk.php');
    expect(LanzouClient.loginUrl, 'https://up.woozooo.com/account.php');

    LanzouClient.apiBase = 'https://pc.woozooo.com';
    expect(LanzouClient.mydiskUrl, 'https://pc.woozooo.com/mydisk.php');
    expect(LanzouClient.loginUrl, 'https://pc.woozooo.com/account.php');
  });

  test('上传入口：域名始终跟随接口域名，只有路径可配', () {
    LanzouClient.apiBase = 'https://pc.woozooo.com';
    LanzouClient.uploadPath = 'fileup.php';
    expect(LanzouClient.uploadUrl, 'https://pc.woozooo.com/fileup.php');

    // 换接口域名，上传域名跟着换
    LanzouClient.apiBase = 'https://up.woozooo.com';
    expect(LanzouClient.uploadUrl, 'https://up.woozooo.com/fileup.php');

    // 上传路径只当路径用：万一被塞了完整地址，也只取最后一段
    LanzouClient.uploadPath = 'https://evil.example/other.php';
    expect(LanzouClient.uploadUrl, 'https://up.woozooo.com/other.php');

    LanzouClient.uploadPath = '';
    expect(LanzouClient.uploadUrl, 'https://up.woozooo.com/html5up.php');
  });

  test('网页版抓取跟随设置：个人中心 / 文件夹统计 / 默认 Referer', () async {
    // 两个域名都过一遍：写死其中一个的实现会在另一档上暴露出来
    for (final host in ['pc', 'up']) {
      LanzouClient.apiBase = 'https://$host.woozooo.com';

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
