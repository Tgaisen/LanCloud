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

  test('删除某条最近使用记录：只删该账号的该条', () async {
    final db = AppDb.instance;
    const account = 'remove-recent-test';
    for (final name in ['A', 'B', 'C']) {
      await db.addRecent(
        account: account,
        kind: 'folder',
        name: name,
        ref: name,
      );
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
    // 另一个账号下的同 ref 记录不应受影响
    await db.addRecent(
      account: 'remove-recent-other',
      kind: 'folder',
      name: 'B',
      ref: 'B',
    );

    await db.removeRecent(account: account, ref: 'B');

    expect((await db.recents(account)).map((r) => r.ref), ['C', 'A']);
    expect((await db.recents('remove-recent-other')).map((r) => r.ref), ['B']);
  });

  test('批量移除快速访问条目（删除文件夹时同步清理）', () async {
    final db = AppDb.instance;
    const account = 'remove-pins-test';
    List<PinItem> mine(List<PinItem> all) =>
        all.where((p) => p.account == account).toList();
    for (final ref in ['p-a', 'p-b', 'p-c']) {
      await db.addPin(account: account, name: ref, ref: ref);
    }

    await db.removePins(['p-a', 'p-c']);
    expect(mine(await db.pins(account)).map((p) => p.ref).toList(), ['p-b']);

    // 空列表直接返回，不影响其它条目
    await db.removePins(const <String>[]);
    expect(mine(await db.pins(account)).length, 1);
  });

  test('快速访问记录目录路径，并支持移到顶部', () async {
    final db = AppDb.instance;
    const account = 'pin-path-test';
    List<PinItem> mine(List<PinItem> all) =>
        all.where((p) => p.account == account).toList();

    await db.addPin(account: account, name: 'A', ref: 'pin-a', path: '根目录/A');
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await db.addPin(
      account: account,
      name: 'B',
      ref: 'pin-b',
      path: '根目录/示例目录/B',
    );

    var list = mine(await db.pins(account));
    expect(list.map((p) => p.name), ['B', 'A']);
    expect(list.first.path, '根目录/示例目录/B');

    await Future<void>.delayed(const Duration(milliseconds: 3));
    await db.movePinToTop('pin-a');
    list = mine(await db.pins(account));
    expect(list.map((p) => p.name), ['A', 'B']);
    expect(list.first.path, '根目录/A');
  });

  test('恢复收藏夹：mergeFavorites 增量合并并按 ref 去重', () async {
    final db = AppDb.instance;
    // 先铺一个已知状态：只有 old
    await db.importTables({
      'favorites': [
        {'kind': 'shareFile', 'name': '旧的', 'ref': 'old', 'created_at': 1},
      ],
    });
    expect((await db.favorites()).map((f) => f.ref).toList(), ['old']);

    // 增量合并：old 重复（跳过）+ new 新增
    await db.importTables({
      'favorites': [
        {'kind': 'shareFile', 'name': '旧的', 'ref': 'old', 'created_at': 1},
        {'kind': 'shareFile', 'name': '新的', 'ref': 'new', 'created_at': 2},
      ],
    }, mergeFavorites: true);
    final merged = (await db.favorites()).map((f) => f.ref).toList();
    expect(merged, containsAll(<String>['old', 'new']));
    expect(merged.length, 2);

    // 不勾选保留时整表覆盖
    await db.importTables({
      'favorites': [
        {'kind': 'shareFile', 'name': '覆盖', 'ref': 'only', 'created_at': 3},
      ],
    });
    expect((await db.favorites()).map((f) => f.ref).toList(), ['only']);
  });

  test('导出表：按备份内容裁剪', () async {
    final db = AppDb.instance;
    expect(
      await db.exportTables(favorites: false, pins: false, recents: false),
      isEmpty,
    );
    expect(
      (await db.exportTables()).keys,
      containsAll(<String>['favorites', 'pins', 'recents', 'downloads']),
    );
    // 已下载标记跟着「最近使用」，单独备份收藏时不导出
    expect(
      (await db.exportTables(
        favorites: true,
        pins: false,
        recents: false,
      )).keys,
      ['favorites'],
    );
  });
}
