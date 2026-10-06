import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_controller.dart';
import 'backup_sections.dart';
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

  /// 本次运行是否已通过敏感内容备份验证：首次通过后不再重复验证。
  bool sensitiveVerified = false;

  Future<void> init() => webdav.load();

  /// 生成备份 JSON：只写入 [sections] 里勾选的内容。
  ///
  /// 账号条目（`activeUid` + `accounts`）只在勾了 Cookie 时写入：Cookie 就存在
  /// 账号条目里，不勾 Cookie 时账号列表只剩昵称可带、恢复端也新建不了账号
  /// （没有凭据），所以不单独占一个分项。
  Future<String> encode({Set<BackupSection> sections = const {}}) async {
    final includeCookies = sections.contains(BackupSection.cookies);
    final payload = <String, Object?>{
      'app': backupAppTag,
      'format': backupFormatVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'includeCookies': includeCookies,
      'sections': [for (final section in sections) section.id]..sort(),
      if (includeCookies) 'activeUid': app.accounts.activeUid,
      if (includeCookies)
        'accounts': app.accounts.exportAccounts(includeCookies: includeCookies),
      if (sections.contains(BackupSection.settings))
        'settings': app.settings.toJson(),
      'tables': await app.db.exportTables(
        favorites: sections.contains(BackupSection.favorites),
        pins: sections.contains(BackupSection.quick),
        recents: sections.contains(BackupSection.recents),
      ),
    };
    // 可选：把 WebDAV 服务器配置（含密码）一起备份
    if (sections.contains(BackupSection.webdavAccount)) {
      payload['webdav'] = {
        'url': webdav.url,
        'username': webdav.username,
        'password': webdav.password,
      };
    }
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 从备份内容恢复：备份里有的部分才覆盖，账号按 uid 合并
  /// （备份不含 Cookie 时保留本地登录态，不会把已登录账号清掉）。
  ///
  /// [mergeFavorites] 为真且备份含收藏夹时做增量合并（按 ref 去重），
  /// 原收藏保留；为假时整表覆盖。
  Future<void> restoreFromString(
    String content, {
    bool mergeFavorites = false,
  }) async {
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
      await app.db.importTables(
        tables.cast<String, dynamic>(),
        mergeFavorites: mergeFavorites,
      );
    }
    final webdavData = decoded['webdav'];
    if (webdavData is Map) {
      await webdav.saveServer(
        url: '${webdavData['url'] ?? ''}',
        username: '${webdavData['username'] ?? ''}',
        password: '${webdavData['password'] ?? ''}',
      );
      await webdav.addBackupSection(BackupSection.webdavAccount);
    }
    await app.reloadFromStorage();
  }

  /// 备份内容里是否含收藏夹数据（恢复前决定要不要给「保留原收藏夹内容」）。
  static bool containsFavorites(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return false;
      final tables = decoded['tables'];
      if (tables is! Map) return false;
      final favorites = tables['favorites'];
      return favorites is List && favorites.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 本地备份：写入临时目录，交给系统「保存文件」对话框导出到用户选择的位置。
  Future<File> exportFile({
    Set<BackupSection> sections = const {},
    DateTime? now,
  }) async {
    final content = await encode(sections: sections);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$filePrefix${stamp(now)}.json'));
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<void> testConnection() async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    await _client().check();
  }

  /// 立即上传备份，返回文件名。成功后同时更新 latest 文件并清理旧备份。
  /// 备份内容用「备份内容」里保存的勾选结果（只影响 WebDAV）。
  Future<String> uploadNow({
    Set<BackupSection>? sections,
    DateTime? now,
  }) async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    final picked = sections ?? webdav.backupSections;
    if (picked.isEmpty) {
      throw const BackupException('请先在「备份内容」里选择要备份的数据');
    }
    final content = await encode(sections: picked);
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
    // 没选备份内容就跳过，不记失败
    if (webdav.backupSections.isEmpty) return;
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
