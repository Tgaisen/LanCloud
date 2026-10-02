import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v4（快速访问还混在 favorites 里）的表结构。
const _v4Schema = [
  'CREATE TABLE favorites(id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'kind TEXT NOT NULL, name TEXT NOT NULL, ref TEXT NOT NULL, '
      'pwd TEXT DEFAULT "", size TEXT DEFAULT "", title TEXT DEFAULT "", '
      'sharer TEXT DEFAULT "", created_at INTEGER NOT NULL)',
  'CREATE TABLE recents(id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'account TEXT NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL, '
      'ref TEXT NOT NULL, pwd TEXT DEFAULT "", opened_at INTEGER NOT NULL)',
  'CREATE TABLE downloads(ref TEXT PRIMARY KEY, name TEXT DEFAULT "", '
      'path TEXT DEFAULT "", created_at INTEGER NOT NULL)',
  'CREATE TABLE transfers(id TEXT PRIMARY KEY, kind TEXT NOT NULL, '
      'name TEXT DEFAULT "", status TEXT NOT NULL, total INTEGER DEFAULT 0, '
      'received INTEGER DEFAULT 0, error TEXT DEFAULT "", '
      'saved_path TEXT DEFAULT "", ref TEXT DEFAULT "", '
      'folder_id TEXT DEFAULT "", created_at INTEGER NOT NULL)',
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v4 → v5：快速访问独立成表并按账号区分，收藏不受影响', () async {
    final path = p.join(await getDatabasesPath(), 'lancloud.db');
    await databaseFactory.deleteDatabase(path);

    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          for (final sql in _v4Schema) {
            await db.execute(sql);
          }
        },
      ),
    );
    await legacy.insert('favorites', {
      'kind': 'pinFolder',
      'name': '蓝云图标包',
      'ref': '3990616',
      'created_at': 1,
    });
    await legacy.insert('favorites', {
      'kind': 'shareFolder',
      'name': '别人分享的文件夹',
      'ref': 'https://example.com/share',
      'created_at': 2,
    });
    await legacy.insert('recents', {
      'account': '523441',
      'kind': 'folder',
      'name': '另一个账号的目录',
      'ref': '9',
      'opened_at': 3,
    });
    await legacy.insert('recents', {
      'account': '556911',
      'kind': 'folder',
      'name': '我的目录',
      'ref': '71',
      'opened_at': 4,
    });
    await legacy.close();

    final db = AppDb.instance;

    // 旧的 pinFolder 迁移到 pins 表，且对所有账号可见
    final pins = await db.pins('556911');
    expect(pins.length, 1);
    expect(pins.first.name, '蓝云图标包');
    expect(pins.first.ref, '3990616');
    expect((await db.pins('523441')).length, 1);
    expect(await db.isPinned('556911', '3990616'), isTrue);

    // favorites 里只剩真正的收藏
    final favorites = await db.favorites();
    expect(favorites.length, 1);
    expect(favorites.first.kind, 'shareFolder');

    // 最近使用按账号隔离
    expect((await db.recents('556911')).single.name, '我的目录');
    expect((await db.recents('523441')).single.name, '另一个账号的目录');

    // 新增的快速访问只属于当前账号
    await db.addPin(account: '523441', name: 'B 目录', ref: '88');
    expect((await db.pins('523441')).length, 2);
    expect(await db.isPinned('523441', '88'), isTrue);
    expect(await db.isPinned('556911', '88'), isFalse);
    expect((await db.pins('556911')).length, 1);

    await db.removePin('88');
    expect((await db.pins('523441')).length, 1);
  });

  test('最近使用按上限裁剪：0 表示不记录', () async {
    final db = AppDb.instance;
    const account = 'limit-test';

    for (var i = 0; i < 5; i++) {
      await db.addRecent(
        account: account,
        kind: 'folder',
        name: '目录 $i',
        ref: '$i',
        limit: 3,
      );
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    final kept = await db.recents(account);
    expect(kept.length, 3);
    expect(kept.first.name, '目录 4');

    // limit = 0：不再记录新条目
    await db.addRecent(
      account: account,
      kind: 'folder',
      name: '不记录',
      ref: 'x',
      limit: 0,
    );
    expect((await db.recents(account)).length, 3);

    // 调小上限立即裁剪
    await db.trimRecents(account, 1);
    expect((await db.recents(account)).single.name, '目录 4');

    // 设为 0 清空
    await db.trimRecents(account, 0);
    expect(await db.recents(account), isEmpty);
  });
}
