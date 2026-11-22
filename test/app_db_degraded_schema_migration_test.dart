import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 高版本表结构被 v11 构建把 user_version 写回后的实际状态：
/// 列已经存在，但版本仍显示为 11。
const _degradedV11Schema = [
  'CREATE TABLE favorites('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, '
      'name TEXT NOT NULL, ref TEXT NOT NULL, pwd TEXT DEFAULT "", '
      'size TEXT DEFAULT "", file_time TEXT DEFAULT "", '
      'requires_password INTEGER, title TEXT DEFAULT "", '
      'sharer TEXT DEFAULT "", folder_snapshot TEXT, '
      'folder_has_update INTEGER DEFAULT 0, folder_update_at INTEGER, '
      'share_status TEXT DEFAULT "unchecked", last_checked_at INTEGER, '
      'created_at INTEGER NOT NULL)',
  'CREATE TABLE recents('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, account TEXT NOT NULL, '
      'kind TEXT NOT NULL, name TEXT NOT NULL, ref TEXT NOT NULL, '
      'pwd TEXT DEFAULT "", share_url TEXT DEFAULT "", '
      'opened_at INTEGER NOT NULL)',
  'CREATE TABLE transfers('
      'id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT DEFAULT "", '
      'status TEXT NOT NULL, total INTEGER DEFAULT 0, '
      'received INTEGER DEFAULT 0, error TEXT DEFAULT "", '
      'saved_path TEXT DEFAULT "", ref TEXT DEFAULT "", '
      'folder_id TEXT DEFAULT "", folder_name TEXT DEFAULT "", '
      'referer TEXT DEFAULT "", pwd TEXT DEFAULT "", '
      'local_path TEXT DEFAULT "", account TEXT DEFAULT "", '
      'created_at INTEGER NOT NULL)',
];

void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('lancloud-v11-schema');
    AppDb.debugDatabaseDirectory = dir.path;

    final path = p.join(dir.path, 'lancloud.db');
    final degraded = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, version) async {
          for (final sql in _degradedV11Schema) {
            await db.execute(sql);
          }
        },
      ),
    );
    await degraded.insert('recents', {
      'account': 'legacy',
      'kind': 'folder',
      'name': '旧目录',
      'ref': 'legacy-folder',
      'share_url': 'https://share.example/legacy',
      'opened_at': 1,
    });
    await degraded.insert('transfers', {
      'id': 'transfer-1',
      'kind': 'upload',
      'name': '旧文件.zip',
      'status': 'pending',
      'folder_name': '旧目录',
      'created_at': 1,
    });
    await degraded.close();
  });

  tearDownAll(() async {
    try {
      await (await AppDb.instance.db).close();
    } catch (_) {}
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('v11 版本号配新表结构：重新升级不重复加列且保留数据', () async {
    final appDb = AppDb.instance;
    final database = await appDb.db;

    final columns = await database.rawQuery('PRAGMA table_info(transfers)');
    expect(columns.where((row) => row['name'] == 'folder_name'), hasLength(1));
    expect(await database.getVersion(), 15);

    final transfer = (await appDb.loadTransfers()).single;
    expect(transfer['name'], '旧文件.zip');
    expect(transfer['folder_name'], '旧目录');

    final recent = (await appDb.recents('legacy')).single;
    expect(recent.name, '旧目录');
    expect(recent.shareUrl, 'https://share.example/legacy');

    await appDb.addRecent(
      account: 'legacy',
      kind: 'folder',
      name: '新目录',
      ref: 'new-folder',
    );
    expect(await appDb.recents('legacy'), hasLength(2));
  });
}
