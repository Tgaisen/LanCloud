// ignore_for_file: avoid_print
// 开发调试脚本：验证 Cookie、文件列表、分享直链与实际下载。
// 用法: dart run tool/check_login.dart <cookie文件路径>
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:lancloud/core/api/lanzou_client.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : '';
  if (path.isEmpty) {
    stderr.writeln('usage: dart run tool/check_login.dart <cookie-file>');
    exit(1);
  }
  final cookie = File(path).readAsStringSync().trim();
  final uid = RegExp(r'ylogin=(\d+)').firstMatch(cookie)?.group(1);
  print('uid parsed: $uid');

  final client = LanzouClient(uid: uid ?? '0')..setCookieHeader(cookie);
  print('verify() => ${await client.verify()}');

  final folders = await client.listFolders('-1');
  print('listFolders => ${folders.folders.length} folders');

  final files = await client.listFiles('-1');
  print('listFiles => ${files.length} files');
  if (files.isEmpty) {
    print('没有可用于测试下载的文件');
    return;
  }

  final f = files.first;
  print('first file: ${f.name} id=${f.id} size=${f.size}');

  final info = await client.shareInfoOfFile(f.id);
  print('share url: ${info.url} hasPwd=${info.pwd.isNotEmpty}');

  final direct = await client.resolveFileShare(info.url, pwd: info.pwd);
  print('direct ok: name=${direct.name} size=${direct.size}');
  print(
    'direct url: ${direct.url.substring(0, direct.url.length > 90 ? 90 : direct.url.length)}...',
  );

  final probe = await client.dio.get<List<int>>(
    direct.url,
    options: Options(
      responseType: ResponseType.bytes,
      headers: {'Range': 'bytes=0-255', 'Referer': info.url},
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  final bytes = probe.data ?? <int>[];
  print(
    'download probe: status=${probe.statusCode} bytes=${bytes.length} '
    'magic=${String.fromCharCodes(bytes.take(4))}',
  );

  final tmpPath = '${Directory.systemTemp.path}\\lancloud_dl_test.bin';
  await client.dio.download(
    direct.url,
    tmpPath,
    options: Options(
      headers: {'Referer': info.url, 'User-Agent': kUserAgent},
      receiveTimeout: const Duration(hours: 1),
    ),
  );
  final downloaded = File(tmpPath);
  final size = await downloaded.length();
  final head = await downloaded
      .openRead(0, 4)
      .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
  print(
    'full download: $size bytes magic=${String.fromCharCodes(head)}',
  );
  await downloaded.delete();
}
