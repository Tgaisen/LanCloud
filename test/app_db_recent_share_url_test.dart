import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _v12RecentsSchema =
    'CREATE TABLE recents(id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'account TEXT NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL, '
    'ref TEXT NOT NULL, pwd TEXT DEFAULT "", opened_at INTEGER NOT NULL)';

void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('lancloud-recent-share-url');
    AppDb.debugDatabaseDirectory = dir.path;

    final path = p.join(dir.path, 'lancloud.db');
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, version) => db.execute(_v12RecentsSchema),
      ),
    );
    await legacy.insert('recents', {
      'account': 'legacy',
      'kind': 'folder',
      'name': '旧目录',
      'ref': 'legacy-folder',
      'opened_at': 1,
    });
    await legacy.close();
  });

  tearDownAll(() async {
    try {
      await (await AppDb.instance.db).close();
    } catch (_) {}
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('v12 → v13：最近使用补 share_url，旧记录保留且缓存为空', () async {
    final db = AppDb.instance;
    final database = await db.db;
    final columns = await database.rawQuery('PRAGMA table_info(recents)');
    expect(columns.map((row) => '${row['name']}'), contains('share_url'));

    final recent = (await db.recents('legacy')).single;
    expect(recent.name, '旧目录');
    expect(recent.shareUrl, isEmpty);
  });

  test('最近使用可写入、单条更新和批量补写分享链接', () async {
    final db = AppDb.instance;
    const account = 'cache-test';
    await db.addRecent(
      account: account,
      kind: 'folder',
      name: '目录 A',
      ref: 'folder-a',
      shareUrl: 'https://share.example/a',
    );
    await db.addRecent(
      account: account,
      kind: 'file',
      name: '文件 B',
      ref: 'file-b',
    );
    await db.addRecent(
      account: account,
      kind: 'folder',
      name: '目录 C',
      ref: 'folder-c',
    );

    final initial = await db.recents(account);
    expect(
      initial.singleWhere((item) => item.ref == 'folder-a').shareUrl,
      'https://share.example/a',
    );

    expect(
      await db.updateRecentShareUrl(
        account: account,
        ref: 'file-b',
        shareUrl: 'https://share.example/b',
      ),
      isTrue,
    );
    expect(
      await db.updateRecentShareUrls(
        account: account,
        shareUrlsByRef: const {
          'folder-c': 'https://share.example/c',
          'missing': 'https://share.example/missing',
        },
      ),
      1,
    );

    final updated = await db.recents(account);
    expect(
      {for (final item in updated) item.ref: item.shareUrl},
      {
        'folder-a': 'https://share.example/a',
        'file-b': 'https://share.example/b',
        'folder-c': 'https://share.example/c',
      },
    );
  });

  test('新备份包含 share_url，旧备份缺少该列时按空串恢复', () async {
    final db = AppDb.instance;
    const account = 'backup-test';
    await db.addRecent(
      account: account,
      kind: 'file',
      name: '备份文件',
      ref: 'backup-file',
      shareUrl: 'https://share.example/backup',
    );

    final exported = await db.exportTables(
      favorites: false,
      pins: false,
      recents: true,
    );
    final grouped = exported['recents'] as Map<String, Object?>;
    final groups = grouped['data'] as List<Object?>;
    final group = groups.cast<Map<String, Object?>>().singleWhere(
      (group) => group['account'] == account,
    );
    final rows = group['data'] as List<Object?>;
    final exportedRow = rows.single as Map<String, Object?>;
    expect(exportedRow['share_url'], 'https://share.example/backup');

    await db.importTables({
      'recents': [
        {
          'account': 'old-backup',
          'kind': 'folder',
          'name': '旧备份目录',
          'ref': 'old-folder',
          'pwd': '',
          'opened_at': 1,
        },
      ],
    });

    final restored = (await db.recents('old-backup')).single;
    expect(restored.shareUrl, isEmpty);
  });
}
