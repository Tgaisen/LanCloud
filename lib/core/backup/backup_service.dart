import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_controller.dart';
import 'webdav_client.dart';
import 'webdav_store.dart';

/// 备份文件格式版本。
/// 1 → 2：快速访问（pins）从收藏独立出来，pins / recents 改为按账号分组。
const int backupFormatVersion = 2;
const String backupAppTag = 'lancloud';

/// 备份与恢复：本地 JSON 文件 + WebDAV 云端。
class BackupService {
  BackupService(this.app, {WebdavStore? webdav})
    : webdav = webdav ?? WebdavStore();

  static BackupService? _instance;

  static BackupService of(AppController app) =>
      _instance ??= BackupService(app);

  /// 测试注入用。
  static set instance(BackupService? value) => _instance = value;

  static const filePrefix = 'lancloud-backup-';
  static const latestName = 'lancloud-latest.json';
  static const maxRemoteFiles = 5;

  final AppController app;
  final WebdavStore webdav;

  Future<void> init() => webdav.load();

  /// 生成备份 JSON。includeCookies 默认关闭：Cookie 等同于账号凭据。
  Future<String> encode({bool includeCookies = false}) async {
    final payload = <String, Object?>{
      'app': backupAppTag,
      'format': backupFormatVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'includeCookies': includeCookies,
      'activeUid': app.accounts.activeUid,
      'accounts': app.accounts.exportAccounts(includeCookies: includeCookies),
      'settings': app.settings.toJson(),
      'tables': await app.db.exportTables(),
    };
    // 可选：把 WebDAV 服务器配置（含密码）一起备份
    if (webdav.includeAccount) {
      payload['webdav'] = {
        'url': webdav.url,
        'username': webdav.username,
        'password': webdav.password,
      };
    }
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 从备份内容恢复：设置与本地表整表覆盖，账号按 uid 合并
  /// （备份不含 Cookie 时保留本地登录态，不会把已登录账号清掉）。
  Future<void> restoreFromString(String content) async {
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const BackupException('备份内容不是有效的 JSON');
    }
    if (decoded is! Map || decoded['app'] != backupAppTag) {
      throw const BackupException('不是 LanCloud 的备份文件');
    }
    final format = (decoded['format'] as num?)?.toInt() ?? 1;
    if (format > backupFormatVersion) {
      throw const BackupException('备份来自更新版本的应用，请先升级再恢复');
    }
    final settings = decoded['settings'];
    if (settings is Map) {
      await app.settings.applyJson(settings.cast<String, Object?>());
    }
    final accounts = decoded['accounts'];
    if (accounts is List) {
      await app.accounts.importAccounts(
        accounts,
        activeSnapshot: '${decoded['activeUid'] ?? ''}',
      );
    }
    final tables = decoded['tables'];
    if (tables is Map) {
      await app.db.importTables(tables.cast<String, dynamic>());
    }
    final webdavData = decoded['webdav'];
    if (webdavData is Map) {
      await webdav.saveServer(
        url: '${webdavData['url'] ?? ''}',
        username: '${webdavData['username'] ?? ''}',
        password: '${webdavData['password'] ?? ''}',
      );
      await webdav.setIncludeAccount(true);
    }
    await app.reloadFromStorage();
  }

  /// 本地备份：写入应用文档目录，返回生成的文件。
  Future<File> saveLocal({bool includeCookies = false, DateTime? now}) async {
    final content = await encode(includeCookies: includeCookies);
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'LanCloud', 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$filePrefix${stamp(now)}.json'));
    await file.writeAsString(content);
    return file;
  }

  Future<void> testConnection() async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    await _client().check();
  }

  /// 立即上传备份，返回文件名。成功后同时更新 latest 文件并清理旧备份。
  Future<String> uploadNow({bool? includeCookies, DateTime? now}) async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    final withCookies = includeCookies ?? webdav.includeCookies;
    final content = await encode(includeCookies: withCookies);
    final name = '$filePrefix${stamp(now)}.json';
    final client = _client();
    try {
      await client.upload(name, content);
      await client.upload(latestName, content);
      await _prune(client);
      await webdav.markBackup();
    } catch (e) {
      await webdav.markBackup(error: '$e');
      rethrow;
    }
    return name;
  }

  /// 云端备份列表（latest 排最前，其余按修改时间倒序）。
  Future<List<WebdavEntry>> remoteBackups() async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    final entries = await _client().list();
    final backups =
        entries
            .where(
              (e) =>
                  e.name == latestName ||
                  (e.name.startsWith(filePrefix) && e.name.endsWith('.json')),
            )
            .toList()
          ..sort((a, b) {
            if (a.name == latestName) return -1;
            if (b.name == latestName) return 1;
            return (b.modified ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  a.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
                );
          });
    return backups;
  }

  Future<void> restoreRemote(String name) async {
    final content = await webdavDownload(name);
    await restoreFromString(content);
  }

  /// 下载云端备份的内容（不直接恢复，便于先做确认）。
  Future<String> webdavDownload(String name) async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    return _client().download(name);
  }

  /// 启动时自动备份：按每天/每周的频率最多跑一次，失败只记录不打扰。
  Future<void> maybeAutoBackup() async {
    await webdav.load();
    if (!webdav.autoBackup || !webdav.configured) return;
    final period = webdav.interval == 'weekly'
        ? const Duration(days: 7)
        : const Duration(days: 1);
    final last = DateTime.fromMillisecondsSinceEpoch(webdav.lastBackupAt);
    if (webdav.lastBackupAt > 0 && DateTime.now().difference(last) < period) {
      return;
    }
    try {
      await uploadNow();
    } on BackupException {
      // 失败原因已由 uploadNow 写进 webdav.lastBackupError
    }
  }

  WebdavClient _client() => WebdavClient(
    url: webdav.url,
    username: webdav.username,
    password: webdav.password,
  );

  /// 云端只保留最新的 maxRemoteFiles 份带时间戳的备份。
  Future<void> _prune(WebdavClient client) async {
    List<WebdavEntry> entries;
    try {
      entries = await client.list();
    } catch (_) {
      return;
    }
    final backups =
        entries
            .where(
              (e) => e.name.startsWith(filePrefix) && e.name.endsWith('.json'),
            )
            .toList()
          ..sort(
            (a, b) => (b.modified ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  a.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
          );
    for (final entry in backups.skip(maxRemoteFiles)) {
      try {
        await client.delete(entry.name);
      } catch (_) {}
    }
  }

  /// 备份文件名用的时间戳：20261002-181500。
  static String stamp(DateTime? now) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
