import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'account_data.dart';

/// 快速访问里固定的一个网盘目录（按账号区分）。
class PinItem {
  PinItem({
    required this.id,
    required this.account,
    required this.name,
    required this.ref,
    this.createdAt = 0,
  });

  final int id;
  final String account;
  final String name;

  /// 网盘目录 id。
  final String ref;
  final int createdAt;
}

class FavoriteItem {
  FavoriteItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.ref,
    this.pwd = '',
    this.size = '',
    this.title = '',
    this.sharer = '',
    this.createdAt = 0,
  });

  final int id;
  final String kind; // file | folder | shareFile | shareFolder
  final String name;
  final String ref; // file id / folder id / share url
  final String pwd;
  final String size;
  final String title;
  final String sharer;
  final int createdAt;
}

class RecentItem {
  RecentItem({
    required this.id,
    required this.account,
    required this.kind,
    required this.name,
    required this.ref,
    this.pwd = '',
    this.openedAt = 0,
  });

  final int id;
  final String account;
  final String kind;
  final String name;
  final String ref;
  final String pwd;
  final int openedAt;
}

class AppDb {
  AppDb._();

  static final AppDb instance = AppDb._();

  Database? _db;

  /// 收藏/最近使用发生变化时自增，供首页即时刷新。
  final ValueNotifier<int> revision = ValueNotifier(0);

  void _touch() => revision.value += 1;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'lancloud.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE favorites('
          'id INTEGER PRIMARY KEY AUTOINCREMENT,'
          'kind TEXT NOT NULL,'
          'name TEXT NOT NULL,'
          'ref TEXT NOT NULL,'
          'pwd TEXT DEFAULT "",'
          'size TEXT DEFAULT "",'
          'title TEXT DEFAULT "",'
          'sharer TEXT DEFAULT "",'
          'created_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE recents('
          'id INTEGER PRIMARY KEY AUTOINCREMENT,'
          'account TEXT NOT NULL,'
          'kind TEXT NOT NULL,'
          'name TEXT NOT NULL,'
          'ref TEXT NOT NULL,'
          'pwd TEXT DEFAULT "",'
          'opened_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE pins('
          'id INTEGER PRIMARY KEY AUTOINCREMENT,'
          'account TEXT NOT NULL,'
          'name TEXT NOT NULL,'
          'ref TEXT NOT NULL,'
          'created_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE downloads('
          'ref TEXT PRIMARY KEY,'
          'name TEXT DEFAULT "",'
          'path TEXT DEFAULT "",'
          'created_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE transfers('
          'id TEXT PRIMARY KEY,'
          'kind TEXT NOT NULL,'
          'name TEXT DEFAULT "",'
          'status TEXT NOT NULL,'
          'total INTEGER DEFAULT 0,'
          'received INTEGER DEFAULT 0,'
          'error TEXT DEFAULT "",'
          'saved_path TEXT DEFAULT "",'
          'ref TEXT DEFAULT "",'
          'folder_id TEXT DEFAULT "",'
          'created_at INTEGER NOT NULL)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS downloads('
            'ref TEXT PRIMARY KEY,'
            'name TEXT DEFAULT "",'
            'path TEXT DEFAULT "",'
            'created_at INTEGER NOT NULL)',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS transfers('
            'id TEXT PRIMARY KEY,'
            'kind TEXT NOT NULL,'
            'name TEXT DEFAULT "",'
            'status TEXT NOT NULL,'
            'total INTEGER DEFAULT 0,'
            'received INTEGER DEFAULT 0,'
            'error TEXT DEFAULT "",'
            'saved_path TEXT DEFAULT "",'
            'ref TEXT DEFAULT "",'
            'folder_id TEXT DEFAULT "",'
            'created_at INTEGER NOT NULL)',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE favorites ADD COLUMN title TEXT DEFAULT ""',
          );
          await db.execute(
            'ALTER TABLE favorites ADD COLUMN sharer TEXT DEFAULT ""',
          );
        }
        if (oldVersion < 5) {
          // 快速访问从收藏表独立出来，并按账号区分；
          // 旧数据没有账号信息，account 留空表示所有账号可见。
          await db.execute(
            'CREATE TABLE IF NOT EXISTS pins('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'account TEXT NOT NULL,'
            'name TEXT NOT NULL,'
            'ref TEXT NOT NULL,'
            'created_at INTEGER NOT NULL)',
          );
          final legacy = await db.query(
            'favorites',
            where: 'kind = ?',
            whereArgs: ['pinFolder'],
          );
          for (final row in legacy) {
            await db.insert('pins', {
              'account': '',
              'name': '${row['name']}',
              'ref': '${row['ref']}',
              'created_at': row['created_at'] ??
                  DateTime.now().millisecondsSinceEpoch,
            });
          }
          await db.delete(
            'favorites',
            where: 'kind = ?',
            whereArgs: ['pinFolder'],
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------- transfers

  Future<void> saveTransfer({
    required String id,
    required String kind,
    required String name,
    required String status,
    int total = 0,
    int received = 0,
    String error = '',
    String savedPath = '',
    String ref = '',
    String folderId = '',
  }) async {
    final database = await db;
    final values = <String, Object?>{
      'kind': kind,
      'name': name,
      'status': status,
      'total': total,
      'received': received,
      'error': error,
      'saved_path': savedPath,
      'ref': ref,
      'folder_id': folderId,
    };
    final updated = await database.update(
      'transfers',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) {
      await database.insert('transfers', {
        'id': id,
        ...values,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<List<Map<String, Object?>>> loadTransfers() async {
    final database = await db;
    return database.query('transfers', orderBy: 'created_at ASC');
  }

  Future<void> deleteTransfer(String id) async {
    final database = await db;
    await database.delete('transfers', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- downloads

  Future<void> markDownloaded({
    required String ref,
    required String name,
    String path = '',
  }) async {
    final database = await db;
    await database.insert(
      'downloads',
      {
        'ref': ref,
        'name': name,
        'path': path,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeDownloaded(List<String> refs) async {
    if (refs.isEmpty) return;
    final database = await db;
    final placeholders = List.filled(refs.length, '?').join(',');
    await database.delete(
      'downloads',
      where: 'ref IN ($placeholders)',
      whereArgs: refs,
    );
  }

  Future<Set<String>> downloadedRefs() async {
    final database = await db;
    final rows = await database.query('downloads', columns: ['ref']);
    return rows.map((r) => '${r['ref']}').toSet();
  }

  // ---------------------------------------------------------------- favorites

  Future<void> addFavorite({
    required String kind,
    required String name,
    required String ref,
    String pwd = '',
    String size = '',
    String title = '',
    String sharer = '',
  }) async {
    final database = await db;
    await database.delete('favorites', where: 'ref = ?', whereArgs: [ref]);
    await database.insert('favorites', {
      'kind': kind,
      'name': name,
      'ref': ref,
      'pwd': pwd,
      'size': size,
      'title': title,
      'sharer': sharer,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _touch();
  }

  Future<void> updateFavorite(
    int id, {
    String? title,
    String? ref,
    String? pwd,
  }) async {
    final database = await db;
    await database.update(
      'favorites',
      {
        'title': ?title,
        'ref': ?ref,
        'pwd': ?pwd,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _touch();
  }

  Future<void> removeFavorite(String ref) async {
    final database = await db;
    await database.delete('favorites', where: 'ref = ?', whereArgs: [ref]);
    _touch();
  }

  Future<void> removeFavoriteById(int id) async {
    final database = await db;
    await database.delete('favorites', where: 'id = ?', whereArgs: [id]);
    _touch();
  }

  Future<bool> isFavorite(String ref) async {
    final database = await db;
    final rows = await database.query('favorites', where: 'ref = ?', whereArgs: [ref]);
    return rows.isNotEmpty;
  }

  Future<List<FavoriteItem>> favorites() async {
    final database = await db;
    final rows = await database.query(
      'favorites',
      where: 'kind != ?',
      whereArgs: ['pinFolder'],
      orderBy: 'created_at DESC',
    );
    return rows
        .map((r) => FavoriteItem(
              id: r['id'] as int,
              kind: '${r['kind']}',
              name: '${r['name']}',
              ref: '${r['ref']}',
              pwd: '${r['pwd']}',
              size: '${r['size']}',
              title: '${r['title'] ?? ''}',
              sharer: '${r['sharer'] ?? ''}',
              createdAt: r['created_at'] as int,
            ))
        .toList();
  }

  // --------------------------------------------------------------------- pins

  /// 某个账号的快速访问（旧数据 account 为空，所有账号都可见）。
  Future<List<PinItem>> pins(String account) async {
    final database = await db;
    final rows = await database.query(
      'pins',
      where: "account = ? OR account = ''",
      whereArgs: [account],
      orderBy: 'created_at DESC',
    );
    return rows
        .map((r) => PinItem(
              id: r['id'] as int,
              account: '${r['account']}',
              name: '${r['name']}',
              ref: '${r['ref']}',
              createdAt: r['created_at'] as int,
            ))
        .toList();
  }

  Future<bool> isPinned(String account, String ref) async {
    final database = await db;
    final rows = await database.query(
      'pins',
      where: "ref = ? AND (account = ? OR account = '')",
      whereArgs: [ref, account],
    );
    return rows.isNotEmpty;
  }

  Future<void> addPin({
    required String account,
    required String name,
    required String ref,
  }) async {
    final database = await db;
    await database.delete('pins', where: 'ref = ?', whereArgs: [ref]);
    await database.insert('pins', {
      'account': account,
      'name': name,
      'ref': ref,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _touch();
  }

  Future<void> removePin(String ref) async {
    final database = await db;
    await database.delete('pins', where: 'ref = ?', whereArgs: [ref]);
    _touch();
  }

  // ------------------------------------------------------------------ recents

  Future<void> addRecent({
    required String account,
    required String kind,
    required String name,
    required String ref,
    String pwd = '',
    int limit = 50,
  }) async {
    if (limit <= 0) return;
    final database = await db;
    await database.delete(
      'recents',
      where: 'account = ? AND ref = ?',
      whereArgs: [account, ref],
    );
    await database.insert('recents', {
      'account': account,
      'kind': kind,
      'name': name,
      'ref': ref,
      'pwd': pwd,
      'opened_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _trimRecents(database, account, limit);
    _touch();
  }

  /// 按上限裁剪某个账号的最近使用（0 表示清空该账号的记录）。
  Future<void> trimRecents(String account, int limit) async {
    final database = await db;
    await _trimRecents(database, account, limit);
    _touch();
  }

  Future<void> _trimRecents(
    Database database,
    String account,
    int limit,
  ) async {
    if (limit <= 0) {
      await database.delete(
        'recents',
        where: 'account = ?',
        whereArgs: [account],
      );
      return;
    }
    await database.rawDelete(
      'DELETE FROM recents WHERE id NOT IN '
      '(SELECT id FROM recents WHERE account = ? ORDER BY opened_at DESC LIMIT ?) '
      'AND account = ?',
      [account, limit, account],
    );
  }

  Future<List<RecentItem>> recents(String account, {int limit = 20}) async {
    final database = await db;
    final rows = await database.query(
      'recents',
      where: 'account = ?',
      whereArgs: [account],
      orderBy: 'opened_at DESC',
      limit: limit,
    );
    return rows
        .map((r) => RecentItem(
              id: r['id'] as int,
              account: '${r['account']}',
              kind: '${r['kind']}',
              name: '${r['name']}',
              ref: '${r['ref']}',
              pwd: '${r['pwd']}',
              openedAt: r['opened_at'] as int,
            ))
        .toList();
  }

  Future<void> clearRecents(String account) async {
    final database = await db;
    await database.delete('recents', where: 'account = ?', whereArgs: [account]);
    _touch();
  }

  // ------------------------------------------------------------------- backup

  /// 备份：导出会随备份迁移的本地表。
  /// 快速访问（pins）与最近使用（recents）按账号分组，其余表平铺。
  /// 传输列表不参与备份（迁移意义不大）。
  Future<Map<String, Object?>> exportTables() async {
    final database = await db;
    return {
      'favorites': await database.query('favorites'),
      'pins': groupByAccount(await database.query('pins')),
      'recents': groupByAccount(await database.query('recents')),
      'downloads': await database.query('downloads'),
    };
  }

  static const _tableColumns = <String, List<String>>{
    'favorites': [
      'id',
      'kind',
      'name',
      'ref',
      'pwd',
      'size',
      'title',
      'sharer',
      'created_at',
    ],
    'pins': ['id', 'account', 'name', 'ref', 'created_at'],
    'recents': ['id', 'account', 'kind', 'name', 'ref', 'pwd', 'opened_at'],
    'downloads': ['ref', 'name', 'path', 'created_at'],
  };

  /// 恢复：整表替换备份里的数据，忽略未知列与非 Map 行。
  /// 兼容两种格式：按账号分组的 `{data_version, data}`，以及早期的平铺数组；
  /// 早期把快速访问混在 favorites 里的备份会自动恢复到 pins 表。
  Future<void> importTables(Map<String, dynamic> data) async {
    final database = await db;
    await database.transaction((txn) async {
      for (final table in _tableColumns.keys) {
        final raw = data[table];
        if (raw == null) continue;
        var rows = rowsOfAccountData(raw);
        if (table == 'favorites') {
          final legacyPins = rows
              .where((row) => '${row['kind']}' == 'pinFolder')
              .toList();
          rows = rows.where((row) => '${row['kind']}' != 'pinFolder').toList();
          for (final pin in legacyPins) {
            await txn.insert(
              'pins',
              {
                'account': '${pin['account'] ?? ''}',
                'name': '${pin['name'] ?? ''}',
                'ref': '${pin['ref'] ?? ''}',
                'created_at': pin['created_at'] ??
                    DateTime.now().millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        final columns = _tableColumns[table]!;
        await txn.delete(table);
        for (final row in rows) {
          final values = <String, Object?>{
            for (final key in columns)
              if (row.containsKey(key)) key: row[key],
          };
          if (values.isEmpty) continue;
          await txn.insert(
            table,
            values,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    _touch();
  }
}
