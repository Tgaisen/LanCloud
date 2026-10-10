import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v6 的表结构（favorites 还没有 ref 索引）。
const _v6Schema = [
  'CREATE TABLE favorites(id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'kind TEXT NOT NULL, name TEXT NOT NULL, ref TEXT NOT NULL, '
      'pwd TEXT DEFAULT "", size TEXT DEFAULT "", title TEXT DEFAULT "", '
      'sharer TEXT DEFAULT "", created_at INTEGER NOT NULL)',
  'CREATE TABLE recents(id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'account TEXT NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL, '
      'ref TEXT NOT NULL, pwd TEXT DEFAULT "", opened_at INTEGER NOT NULL)',
  'CREATE TABLE pins(id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'account TEXT NOT NULL, name TEXT NOT NULL, ref TEXT NOT NULL, '
      'path TEXT DEFAULT "", created_at INTEGER NOT NULL)',
  'CREATE TABLE downloads(ref TEXT PRIMARY KEY, name TEXT DEFAULT "", '
      'path TEXT DEFAULT "", created_at INTEGER NOT NULL)',
  'CREATE TABLE transfers(id TEXT PRIMARY KEY, kind TEXT NOT NULL, '
      'name TEXT DEFAULT "", status TEXT NOT NULL, total INTEGER DEFAULT 0, '
      'received INTEGER DEFAULT 0, error TEXT DEFAULT "", '
      'saved_path TEXT DEFAULT "", ref TEXT DEFAULT "", '
      'folder_id TEXT DEFAULT "", created_at INTEGER NOT NULL)',
];

void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 自己开一个独立目录：测试文件之间是并行跑的，别和 app_db_test 抢同一个库
    dir = await Directory.systemTemp.createTemp('lancloud-v7-test');
    AppDb.debugDatabaseDirectory = dir.path;
  });

  tearDownAll(() async {
    // 先关掉库句柄，否则临时目录删不掉（Windows 上文件还被占用）
    try {
      await (await AppDb.instance.db).close();
    } catch (_) {}
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('v6 → v7：收藏表补上 ref 索引，收藏数据本身不受影响', () async {
    final path = p.join(dir.path, 'lancloud.db');
    await databaseFactory.deleteDatabase(path);

    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          for (final sql in _v6Schema) {
            await db.execute(sql);
          }
        },
      ),
    );
    await legacy.insert('favorites', {
      'kind': 'shareFile',
      'name': 'a.zip',
      'ref': 'https://share.example/f1',
      'created_at': 1,
    });
    await legacy.close();

    final db = AppDb.instance;

    // 数据还在，判定照常可用
    expect(await db.isFavorite('https://share.example/f1'), isTrue);
    expect(await db.isFavorite('https://share.example/none'), isFalse);
    expect((await db.favorites()).length, 1);

    // 索引真的建出来了，而且查询走的是它
    final indexes = await (await db.db).rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
      ['idx_favorites_ref'],
    );
    expect(indexes, hasLength(1));

    final plan = await (await db.db).rawQuery(
      'EXPLAIN QUERY PLAN SELECT * FROM favorites WHERE ref = ?',
      ['https://share.example/f1'],
    );
    expect(
      plan.map((row) => '${row['detail']}').join(' '),
      contains('idx_favorites_ref'),
    );
  });
}
