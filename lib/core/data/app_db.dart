import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class FavoriteItem {
  FavoriteItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.ref,
    this.pwd = '',
    this.size = '',
    this.createdAt = 0,
  });

  final int id;
  final String kind; // file | folder | shareFile | shareFolder
  final String name;
  final String ref; // file id / folder id / share url
  final String pwd;
  final String size;
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

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'lancloud.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE favorites('
          'id INTEGER PRIMARY KEY AUTOINCREMENT,'
          'kind TEXT NOT NULL,'
          'name TEXT NOT NULL,'
          'ref TEXT NOT NULL,'
          'pwd TEXT DEFAULT "",'
          'size TEXT DEFAULT "",'
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
  }) async {
    final database = await db;
    await database.delete('favorites', where: 'ref = ?', whereArgs: [ref]);
    await database.insert('favorites', {
      'kind': kind,
      'name': name,
      'ref': ref,
      'pwd': pwd,
      'size': size,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> removeFavorite(String ref) async {
    final database = await db;
    await database.delete('favorites', where: 'ref = ?', whereArgs: [ref]);
  }

  Future<bool> isFavorite(String ref) async {
    final database = await db;
    final rows = await database.query('favorites', where: 'ref = ?', whereArgs: [ref]);
    return rows.isNotEmpty;
  }

  Future<List<FavoriteItem>> favorites() async {
    final database = await db;
    final rows = await database.query('favorites', orderBy: 'created_at DESC');
    return rows
        .map((r) => FavoriteItem(
              id: r['id'] as int,
              kind: '${r['kind']}',
              name: '${r['name']}',
              ref: '${r['ref']}',
              pwd: '${r['pwd']}',
              size: '${r['size']}',
              createdAt: r['created_at'] as int,
            ))
        .toList();
  }

  // ------------------------------------------------------------------ recents

  Future<void> addRecent({
    required String account,
    required String kind,
    required String name,
    required String ref,
    String pwd = '',
  }) async {
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
    await database.rawDelete(
      'DELETE FROM recents WHERE id NOT IN '
      '(SELECT id FROM recents WHERE account = ? ORDER BY opened_at DESC LIMIT 100) '
      'AND account = ?',
      [account, account],
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
  }
}
