import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_dependencies.dart';
import 'backup_crypto.dart';
import 'backup_sections.dart';
import 'webdav_client.dart';
import 'webdav_store.dart';

/// 备份文件格式版本。
/// 1 → 2：快速访问（pins）从收藏独立出来，pins / recents 改为按账号分组。
/// 2 → 3：支持可选的整包口令加密。
const int backupFormatVersion = 3;
const String backupAppTag = 'lancloud';

/// 备份中的一个账号条目。Cookie 只用于恢复流程的内存预检，不直接展示。
class BackupAccountPreview {
  const BackupAccountPreview({
    required this.uid,
    required this.nickname,
    required this.cookie,
  });

  final String uid;
  final String nickname;
  final String cookie;

  bool get hasCookie => cookie.trim().isNotEmpty;
  String get displayName => nickname.trim().isEmpty ? uid : nickname;
}

/// 不写入任何存储的备份摘要，用于恢复前确认和登录态预检。
class BackupPreview {
  const BackupPreview({
    required this.format,
    required this.createdAt,
    required this.sections,
    required this.accounts,
    required this.activeUid,
    required this.hasFavorites,
    required this.hasWebdavCredentials,
  });

  final int format;
  final DateTime? createdAt;
  final Set<BackupSection> sections;
  final List<BackupAccountPreview> accounts;
  final String activeUid;
  final bool hasFavorites;
  final bool hasWebdavCredentials;

  List<BackupAccountPreview> get cookieAccounts =>
      accounts.where((account) => account.hasCookie).toList(growable: false);

  bool get hasCookies => cookieAccounts.isNotEmpty;

  /// Cookie 或 WebDAV 密码都属于需要本地身份验证的凭据。
  bool get hasSensitiveData => hasCookies || hasWebdavCredentials;

  /// 首选备份中记录的当前账号；它不可用时退到第一个带 Cookie 的账号。
  BackupAccountPreview? get suggestedAccount {
    for (final account in cookieAccounts) {
      if (account.uid == activeUid) return account;
    }
    return cookieAccounts.isEmpty ? null : cookieAccounts.first;
  }
}

/// 备份与恢复：本地 JSON 文件 + WebDAV 云端。
class BackupService {
  BackupService(this.dependencies, {WebdavStore? webdav})
    : webdav = webdav ?? WebdavStore();

  static BackupService? _instance;

  static BackupService of(BackupDependencies dependencies) =>
      _instance ??= BackupService(dependencies);

  /// 测试注入用。
  static set instance(BackupService? value) => _instance = value;

  static const filePrefix = 'lancloud-backup-';
  static const latestName = 'lancloud-latest.json';
  static const maxRemoteFiles = 5;

  final BackupDependencies dependencies;
  final WebdavStore webdav;

  /// 本次运行是否已通过敏感内容备份验证：首次通过后不再重复验证。
  bool sensitiveVerified = false;

  Future<void> init() => webdav.load();

  /// 生成备份 JSON：只写入 [sections] 里勾选的内容。
  ///
  /// 账号条目（`activeUid` + `accounts`）只在勾了 Cookie 时写入：Cookie 就存在
  /// 账号条目里，不勾 Cookie 时账号列表只剩昵称可带、恢复端也新建不了账号
  /// （没有凭据），所以不单独占一个分项。
  Future<String> encode({
    Set<BackupSection> sections = const {},
    String? passphrase,
  }) async {
    final includeCookies = sections.contains(BackupSection.cookies);
    final payload = <String, Object?>{
      'app': backupAppTag,
      'format': backupFormatVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'includeCookies': includeCookies,
      'sections': [for (final section in sections) section.id]..sort(),
      if (includeCookies) 'activeUid': dependencies.accounts.activeUid,
      if (includeCookies)
        'accounts': dependencies.accounts.exportAccounts(
          includeCookies: includeCookies,
        ),
      if (sections.contains(BackupSection.settings))
        'settings': dependencies.settings.toJson(),
      'tables': await dependencies.db.exportTables(
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
        'backupPassphrase': webdav.backupPassphrase,
        'path': webdav.path,
        // 「备份内容」勾选项与「自动备份」开关跟着账号配置一起走：
        // 换设备恢复后不用再手动勾一遍
        'autoBackup': webdav.autoBackup,
        'backupSections': [
          for (final section in webdav.backupSections) section.id,
        ]..sort(),
      };
    }
    final plaintext = const JsonEncoder.withIndent('  ').convert(payload);
    final pass = passphrase ?? '';
    if (pass.isNotEmpty) {
      final encrypted = await BackupCrypto.encrypt(plaintext, passphrase: pass);
      return const JsonEncoder.withIndent('  ').convert({
        'app': backupAppTag,
        'format': backupFormatVersion,
        'encryption': encrypted,
      });
    }
    if (sections.any((section) => section.sensitive)) {
      throw const BackupException('备份包含敏感信息，必须设置备份密码');
    }
    return plaintext;
  }

  /// 从备份内容恢复：备份里有的部分才覆盖，账号按 uid 合并
  /// （备份不含 Cookie 时保留本地登录态，不会把已登录账号清掉）。
  ///
  /// [mergeFavorites] 为真且备份含收藏夹时做增量合并（按 ref 去重），
  /// 原收藏保留；为假时整表覆盖。
  ///
  /// [restoreAccounts] 为假时只恢复设置、收藏和快速访问等普通数据，
  /// 不导入账号、Cookie 或 WebDAV 密码；用于备份登录态失效、离线或用户
  /// 主动只恢复数据。
  Future<void> restoreFromString(
    String content, {
    String? passphrase,
    bool mergeFavorites = false,
    bool restoreAccounts = true,
  }) async {
    final plaintext = await decryptIfNeeded(content, passphrase: passphrase);
    final decoded = _decode(plaintext);
    final settings = decoded['settings'];
    if (settings is Map) {
      await dependencies.settings.applyJson(settings.cast<String, Object?>());
    }
    final accounts = decoded['accounts'];
    if (restoreAccounts && accounts is List) {
      await dependencies.accounts.importAccounts(
        accounts,
        activeSnapshot: '${decoded['activeUid'] ?? ''}',
      );
    }
    final tables = decoded['tables'];
    if (tables is Map) {
      await dependencies.db.importTables(
        tables.cast<String, dynamic>(),
        mergeFavorites: mergeFavorites,
      );
    }
    final webdavData = decoded['webdav'];
    if (restoreAccounts && webdavData is Map) {
      await webdav.saveServer(
        url: '${webdavData['url'] ?? ''}',
        username: '${webdavData['username'] ?? ''}',
        password: '${webdavData['password'] ?? ''}',
        backupPassphrase: '${webdavData['backupPassphrase'] ?? ''}',
        // 旧备份没有 path：URL 本身就是备份目录，按「/」恢复
        path: '${webdavData['path'] ?? '/'}',
      );
      final sectionIds = webdavData['backupSections'];
      if (sectionIds is List) {
        await webdav.setBackupSections(
          BackupSection.fromIds(sectionIds.map((id) => '$id')),
        );
      }
      await webdav.addBackupSection(BackupSection.webdavAccount);
      // 自动备份要求至少有一个备份分项：先恢复分项，再恢复开关状态。
      final autoBackup = webdavData['autoBackup'];
      if (autoBackup is bool) await webdav.setAutoBackup(autoBackup);
    }
    await dependencies.reloadFromStorage();
  }

  /// 解析并校验备份，返回不落盘的摘要供恢复向导展示。
  static BackupPreview inspect(String content) {
    final decoded = _decode(content);
    if (BackupCrypto.isEncryptedEnvelope(decoded)) {
      throw const BackupException('此备份已加密，请先输入备份密码');
    }
    final rawSections = decoded['sections'];
    final sections = rawSections is List
        ? BackupSection.fromIds(rawSections.map((value) => '$value'))
        : <BackupSection>{};
    final rawAccounts = decoded['accounts'];
    final accounts = <BackupAccountPreview>[];
    if (rawAccounts is List) {
      for (final raw in rawAccounts) {
        if (raw is! Map) continue;
        final uid = '${raw['uid'] ?? ''}'.trim();
        if (uid.isEmpty) continue;
        accounts.add(
          BackupAccountPreview(
            uid: uid,
            nickname: '${raw['nickname'] ?? ''}',
            cookie: '${raw['cookie'] ?? ''}',
          ),
        );
      }
    }
    final createdAt = decoded['createdAt'];
    final tables = decoded['tables'];
    final favorites = tables is Map ? tables['favorites'] : null;
    final webdav = decoded['webdav'];
    return BackupPreview(
      format: (decoded['format'] as num?)?.toInt() ?? 1,
      createdAt: createdAt is num
          ? DateTime.fromMillisecondsSinceEpoch(createdAt.toInt())
          : null,
      sections: sections,
      accounts: accounts,
      activeUid: '${decoded['activeUid'] ?? ''}',
      hasFavorites: favorites is List && favorites.isNotEmpty,
      hasWebdavCredentials:
          sections.contains(BackupSection.webdavAccount) ||
          (webdav is Map && '${webdav['password'] ?? ''}'.isNotEmpty),
    );
  }

  /// 检测文件是否使用整包口令加密。
  static bool isEncrypted(String content) {
    try {
      return BackupCrypto.isEncryptedEnvelope(_decode(content));
    } catch (_) {
      return false;
    }
  }

  /// 加密备份先验证口令并解出完整明文；旧版明文原样返回。
  static Future<String> decryptIfNeeded(
    String content, {
    String? passphrase,
  }) async {
    final envelope = _decode(content);
    if (!BackupCrypto.isEncryptedEnvelope(envelope)) return content;
    final pass = passphrase ?? '';
    if (pass.trim().isEmpty) {
      throw const BackupException('此备份已加密，请输入备份密码');
    }
    final encryption = envelope['encryption'];
    try {
      return await BackupCrypto.decrypt(
        (encryption as Map).cast<String, dynamic>(),
        passphrase: pass,
      );
    } on BackupCryptoException catch (error) {
      throw BackupException(error.message);
    }
  }

  /// 处理口令后返回摘要，供恢复向导展示。
  static Future<BackupPreview> inspectContent(
    String content, {
    String? passphrase,
  }) async => inspect(await decryptIfNeeded(content, passphrase: passphrase));

  static Map<String, dynamic> _decode(String content) {
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
    return decoded.cast<String, dynamic>();
  }

  /// 备份内容里是否含收藏夹数据（恢复前决定要不要给「保留原收藏夹内容」）。
  static bool containsFavorites(String content) {
    try {
      return inspect(content).hasFavorites;
    } catch (_) {
      return false;
    }
  }

  /// 本地备份：写入临时目录，交给系统「保存文件」对话框导出到用户选择的位置。
  Future<File> exportFile({
    Set<BackupSection> sections = const {},
    String? passphrase,
    DateTime? now,
  }) async {
    final content = await encode(sections: sections, passphrase: passphrase);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$filePrefix${stamp(now)}.json'));
    await file.writeAsString(content, flush: true);
    return file;
  }

  Future<void> testConnection() async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    final client = _client();
    // 备份目录可能还没建出来：先确保它可以创建 / 存在，再测连接
    await client.ensureDirectory();
    await client.check();
  }

  /// 立即上传备份，返回文件名。成功后同时更新 latest 文件并清理旧备份。
  /// 备份内容用「备份内容」里保存的勾选结果（只影响 WebDAV）。
  Future<String> uploadNow({
    Set<BackupSection>? sections,
    DateTime? now,
    void Function()? onGenerated,
  }) async {
    await webdav.load();
    if (!webdav.configured) throw const BackupException('请先填写 WebDAV 地址');
    final picked = sections ?? webdav.backupSections;
    if (picked.isEmpty) {
      throw const BackupException('请先在「备份选项」里选择要备份的数据');
    }
    final content = await encode(
      sections: picked,
      passphrase: webdav.backupPassphrase,
    );
    onGenerated?.call();
    final name = '$filePrefix${stamp(now)}.json';
    final client = _client();
    try {
      // 路径可能是第一次使用：不存在的目录先建出来（已存在时服务器回 405）
      await client.ensureDirectory();
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
    // 目录还没建出来时按「没有备份」处理，不把 404 当错误弹给用户
    return _backupEntries(await _client().listOrEmpty());
  }

  /// 使用恢复向导中临时填写的 WebDAV 连接读取备份列表，不保存连接配置。
  Future<List<WebdavEntry>> remoteBackupsWithConnection({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    final client = _temporaryClient(
      url: url,
      username: username,
      password: password,
      path: path,
    );
    return _backupEntries(await client.listOrEmpty());
  }

  List<WebdavEntry> _backupEntries(List<WebdavEntry> entries) {
    return entries
        .where(
          (entry) =>
              entry.name == latestName ||
              (entry.name.startsWith(filePrefix) &&
                  entry.name.endsWith('.json')),
        )
        .toList()
      ..sort((a, b) {
        if (a.name == latestName) return -1;
        if (b.name == latestName) return 1;
        return (b.modified ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          a.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
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

  /// 使用临时 WebDAV 连接下载备份，不写入本地连接配置。
  Future<String> webdavDownloadWithConnection(
    String name, {
    required String url,
    required String username,
    required String password,
    required String path,
  }) {
    return _temporaryClient(
      url: url,
      username: username,
      password: password,
      path: path,
    ).download(name);
  }

  /// 启动时自动备份：按每天/每周的频率最多跑一次，失败只记录不打扰。
  Future<void> maybeAutoBackup() async {
    await webdav.load();
    if (!webdav.autoBackup || !webdav.configured) return;
    if (webdav.backupSections.any((section) => section.sensitive) &&
        !webdav.hasBackupPassphrase) {
      return;
    }
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
    url: webdav.backupUrl,
    username: webdav.username,
    password: webdav.password,
  );

  WebdavClient _temporaryClient({
    required String url,
    required String username,
    required String password,
    required String path,
  }) {
    final temporary = WebdavStore()
      ..url = url.trim()
      ..username = username.trim()
      ..password = password
      ..path = WebdavStore.normalizePath(path);
    return WebdavClient(
      url: temporary.backupUrl,
      username: temporary.username,
      password: temporary.password,
    );
  }

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
