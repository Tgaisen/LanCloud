import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v7 的表结构（transfers 还没有 referer / pwd / local_path 三列）。
const _v7Schema = [
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
    // 独立目录：测试文件之间并行跑，别和别的迁移测试抢同一个库
    dir = await Directory.systemTemp.createTemp('lancloud-v8-test');
    AppDb.debugDatabaseDirectory = dir.path;
  });

  tearDownAll(() async {
    // 先关掉库句柄，否则 Windows 上临时目录删不掉（文件仍被占用）
    try {
      await (await AppDb.instance.db).close();
    } catch (_) {}
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('v7 → 最新：transfers 依次补上分享链接、密码与上传源路径列', () async {
    final path = p.join(dir.path, 'lancloud.db');
    await databaseFactory.deleteDatabase(path);

    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          for (final sql in _v7Schema) {
            await db.execute(sql);
          }
          await db.execute('CREATE INDEX idx_favorites_ref ON favorites(ref)');
        },
      ),
    );
    await legacy.insert('transfers', {
      'id': 'd1',
      'kind': 'download',
      'name': 'a.zip',
      'status': 'failed',
      'error': '网络错误',
      'created_at': 1,
    });
    await legacy.close();

    final db = AppDb.instance;
    final rows = await db.loadTransfers();
    expect(rows, hasLength(1));
    expect('${rows.single['name']}', 'a.zip');
    // 旧记录没有这些字段：新列默认空串
    expect('${rows.single['referer'] ?? ''}', '');
    expect('${rows.single['pwd'] ?? ''}', '');
    expect('${rows.single['local_path'] ?? ''}', '');
    expect('${rows.single['account'] ?? ''}', '');

    // 新写入可以把分享链接 + 密码 + 上传源路径 + 账号存进去（重启后重试要用）
    await db.saveTransfer(
      id: 'd1',
      kind: 'download',
      name: 'a.zip',
      status: 'failed',
      referer: 'https://share.example/f1',
      pwd: '1abc',
      localPath: '/tmp/up.zip',
      account: '12345',
    );
    final again = (await db.loadTransfers()).single;
    expect('${again['referer']}', 'https://share.example/f1');
    expect('${again['pwd']}', '1abc');
    expect('${again['local_path']}', '/tmp/up.zip');
    expect('${again['account']}', '12345');
  });
}
