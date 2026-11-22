import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('lancloud-db-delete');
    AppDb.debugDatabaseDirectory = dir.path;
  });

  tearDownAll(() async {
    AppDb.debugDatabaseDirectory = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('关闭并删除数据库：文件从应用数据目录移除', () async {
    final appDb = AppDb.instance;
    final database = await appDb.db;
    await database.insert('pins', {
      'account': 'u1',
      'name': '目录',
      'ref': 'f1',
      'created_at': 1,
    });
    final path = p.join(dir.path, 'lancloud.db');
    expect(await File(path).exists(), isTrue);

    await appDb.closeAndDelete();

    expect(await File(path).exists(), isFalse);
    await expectLater(appDb.db, throwsStateError);
  });
}
