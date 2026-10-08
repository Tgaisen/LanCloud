import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lancloud_cache_test');
    AppCache.directoryProvider = () async => dir;
  });

  tearDown(() {
    AppCache.directoryProvider = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void write(String relative, int bytes) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 0));
  }

  test('移动端：缓存目录是应用私有的，整个目录都可清理', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    write('picked/a.bin', 100); // 本应用：选文件副本
    write('drop/b.bin', 50); // 本应用：拖拽副本
    write('lancloud-backup-x.json', 25); // 本应用：备份导出残留
    write('WebView/cache.bin', 1000); // 网页缓存：也算缓存

    expect(await AppCache.size(), 1175);
    expect(await AppCache.clear(), 1175);
    expect(await AppCache.size(), 0);
    expect(dir.listSync(), isEmpty);
  });

  test('桌面端：只清理本应用自己的条目，不碰 %TEMP% 里的其它文件', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    write('picked/a.bin', 100); // 本应用：选文件副本
    write('lancloud-backup-x.json', 25); // 本应用：备份导出残留
    write('other-app/tmp.bin', 1000); // 其它应用的临时文件：不能动

    expect(await AppCache.size(), 125);
    expect(await AppCache.clear(), 125);
    expect(File(p.join(dir.path, 'picked', 'a.bin')).existsSync(), isFalse);
    expect(
      File(p.join(dir.path, 'lancloud-backup-x.json')).existsSync(),
      isFalse,
    );
    // 其它应用的临时文件必须保留
    expect(File(p.join(dir.path, 'other-app', 'tmp.bin')).existsSync(), isTrue);
  });

  test('拿不到临时目录时返回 null，不抛异常', () async {
    AppCache.directoryProvider = () async => null;
    expect(await AppCache.size(), isNull);
    expect(await AppCache.clear(), isNull);
  });
}
