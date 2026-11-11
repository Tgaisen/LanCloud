import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _v13RecentsSchema =
    'CREATE TABLE recents('
    'id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'account TEXT NOT NULL, '
    'kind TEXT NOT NULL, '
    'name TEXT NOT NULL, '
    'ref TEXT NOT NULL, '
    'pwd TEXT DEFAULT "", '
    'share_url TEXT DEFAULT "", '
    'opened_at INTEGER NOT NULL)';

void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('lancloud-db-downgrade');
    AppDb.debugDatabaseDirectory = dir.path;

    final path = p.join(dir.path, 'lancloud.db');
    final current = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (db, version) => db.execute(_v13RecentsSchema),
      ),
    );
    await current.insert('recents', {
      'account': 'legacy',
      'kind': 'folder',
      'name': '旧目录',
      'ref': 'legacy-folder',
      'share_url': 'https://share.example/legacy',
      'opened_at': 1,
    });
    await current.close();

    // 模拟曾运行 v13 后安装 v12 构建：sqflite 只回写 user_version，
    // 不会删除已有的 share_url 列。
    final downgraded = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 12),
    );
    await downgraded.close();
  });

  tearDownAll(() async {
    try {
      await (await AppDb.instance.db).close();
    } catch (_) {}
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('v13 → v12 降级后重新升级：share_url 迁移保持幂等且不丢数据', () async {
    final appDb = AppDb.instance;
    final database = await appDb.db;

    final columns = await database.rawQuery('PRAGMA table_info(recents)');
    expect(columns.where((row) => row['name'] == 'share_url'), hasLength(1));
    expect(await database.getVersion(), 13);

    final recent = (await appDb.recents('legacy')).single;
    expect(recent.name, '旧目录');
    expect(recent.shareUrl, 'https://share.example/legacy');
  });
}
