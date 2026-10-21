import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/secure_storage.dart';
import 'backup_sections.dart';

/// WebDAV 备份配置与自动备份状态。
///
/// 地址、用户名、密码、路径作为一个完整账号记录放安全存储；自动备份开关、
/// 频率和上次执行结果等运行状态仍放普通偏好。
class WebdavStore {
  static const _secureAccount = 'lancloud_webdav_account_v1';
  static const _legacySecurePassword = 'lancloud_webdav_password';

  // v10 及以前放在 SharedPreferences 里的账号字段；仅在迁移时读取和清理。
  static const _keyUrl = 'webdav_url';
  static const _keyUser = 'webdav_user';
  static const _keyPath = 'webdav_path';
  static const _keyAuto = 'webdav_auto';
  static const _keyInterval = 'webdav_interval';
  static const _keyBackupSections = 'webdav_backup_sections';
  static const _keyLastAt = 'webdav_last_backup_at';
  static const _keyLastError = 'webdav_last_backup_error';
  static const _storage = lanCloudSecureStorage;

  String url = '';
  String username = '';
  String password = '';
  bool autoBackup = false;

  /// 备份 / 恢复目录：相对服务器地址的路径（默认 `/LanCloud`）。
  ///
  /// `/` 表示直接用地址所在目录——旧配置升级后默认就是这个，备份仍落在
  /// 原来的位置，不会因为多了一层目录而「找不到」已有备份。
  String path = defaultPath;

  /// 新配置默认把备份放在服务器地址下的这个目录里。
  static const String defaultPath = '/LanCloud';

  /// daily | weekly
  String interval = 'daily';

  /// WebDAV 备份内容（只影响 WebDAV 上传，与本地备份的每次勾选互不影响）。
  Set<BackupSection> backupSections = <BackupSection>{};

  int lastBackupAt = 0;
  String lastBackupError = '';

  /// 已存在地址但四项连接信息不完整：保留看得见的信息并等待重新配置。
  bool get needsConfiguration => url.trim().isNotEmpty && !configured;

  /// 只有地址、用户名、密码和路径齐全时才允许网络操作及自动备份。
  bool get configured =>
      url.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty &&
      path.trim().isNotEmpty;

  /// 有效的备份目录（服务器地址 + 路径），WebdavClient 的所有操作都用它。
  String get backupUrl {
    final base = url.trim();
    if (base.isEmpty) return '';
    final dir = normalizePath(path);
    if (dir.isEmpty || dir == '/') return base;
    final sep = base.endsWith('/') ? '' : '/';
    return '$base$sep${dir.substring(1)}/';
  }

  /// 规范化备份路径：去掉首尾空白、补前导 `/`、去掉末尾多余 `/`；
  /// 单独的 `/` 表示「地址所在目录」。
  static String normalizePath(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return '';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    while (normalized.length > 1 && normalized.startsWith('//')) {
      normalized = normalized.substring(1);
    }
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    autoBackup = prefs.getBool(_keyAuto) ?? false;
    interval = prefs.getString(_keyInterval) ?? 'daily';
    backupSections = BackupSection.fromIds(
      prefs.getStringList(_keyBackupSections) ?? const [],
    );
    lastBackupAt = prefs.getInt(_keyLastAt) ?? 0;
    lastBackupError = prefs.getString(_keyLastError) ?? '';

    final stored = await readSecureAccount();
    if (stored != null) {
      _applyAccount(stored);
      await _removeLegacyCredentials(prefs);
    } else {
      final legacyUrl = prefs.getString(_keyUrl) ?? '';
      final legacyUser = prefs.getString(_keyUser) ?? '';
      final legacyPath = prefs.getString(_keyPath);
      final legacyPassword = await readLegacyPassword();
      _applyLegacyAccount(
        url: legacyUrl,
        username: legacyUser,
        password: legacyPassword,
        path: legacyPath,
      );

      if (url.isNotEmpty || username.isNotEmpty || password.isNotEmpty) {
        try {
          final data = _accountData();
          await writeSecureAccount(data);
          final verified = await readSecureAccount();
          if (_sameAccount(data, verified)) {
            await _removeLegacyCredentials(prefs);
          }
        } catch (_) {
          // 写入或回读失败时保留旧字段与旧密码，本次仍用内存值工作；
          // 下次 load 会重试迁移，不把可用配置提前删掉。
        }
      }
    }
    if (autoBackup && !configured) {
      autoBackup = false;
      await prefs.setBool(_keyAuto, false);
    }
  }

  Map<String, String> _accountData() => {
    'url': url,
    'username': username,
    'password': password,
    'path': path,
  };

  void _applyAccount(Map<String, String> data) {
    url = (data['url'] ?? '').trim();
    username = (data['username'] ?? '').trim();
    password = data['password'] ?? '';
    final storedPath = data['path'];
    path = storedPath == null || storedPath.isEmpty
        ? (url.isEmpty ? defaultPath : '/')
        : normalizePath(storedPath);
  }

  void _applyLegacyAccount({
    required String url,
    required String username,
    required String password,
    required String? path,
  }) {
    _applyAccount({
      'url': url,
      'username': username,
      'password': password,
      'path': path ?? (url.trim().isEmpty ? defaultPath : '/'),
    });
  }

  bool _sameAccount(Map<String, String> a, Map<String, String>? b) =>
      b != null &&
      a['url'] == b['url'] &&
      a['username'] == b['username'] &&
      a['password'] == b['password'] &&
      a['path'] == b['path'];

  /// 读取完整账号记录；单独抽出来便于测试替换安全存储插件。
  Future<Map<String, String>?> readSecureAccount() async {
    try {
      final raw = await _storage.read(key: _secureAccount);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSecureAccount(Map<String, String> value) async {
    await _storage.write(key: _secureAccount, value: jsonEncode(value));
  }

  Future<void> deleteSecureAccount() async {
    await _storage.delete(key: _secureAccount);
  }

  Future<String> readLegacyPassword() async {
    try {
      return await _storage.read(key: _legacySecurePassword) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> deleteLegacyPassword() async {
    try {
      await _storage.delete(key: _legacySecurePassword);
    } catch (_) {}
  }

  Future<void> _removeLegacyCredentials(SharedPreferences prefs) async {
    await prefs.remove(_keyUrl);
    await prefs.remove(_keyUser);
    await prefs.remove(_keyPath);
    await deleteLegacyPassword();
  }

  Future<void> saveServer({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    this.url = url.trim();
    this.username = username.trim();
    this.password = password;
    this.path = normalizePath(path);
    final prefs = await SharedPreferences.getInstance();
    if (this.url.isEmpty) {
      await deleteSecureAccount();
    } else {
      final data = _accountData();
      await writeSecureAccount(data);
      final verified = await readSecureAccount();
      if (!_sameAccount(data, verified)) {
        throw StateError('WebDAV 账号安全存储校验失败');
      }
    }
    await _removeLegacyCredentials(prefs);
    if (!configured && autoBackup) {
      autoBackup = false;
      await prefs.setBool(_keyAuto, false);
    }
  }

  Future<void> setAutoBackup(bool value) async {
    autoBackup = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAuto, value);
  }

  Future<void> setInterval(String value) async {
    interval = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInterval, value);
  }

  /// 保存 WebDAV 备份内容（「备份内容」弹窗确认时调用）。
  Future<void> setBackupSections(Set<BackupSection> value) async {
    backupSections = {...value};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyBackupSections,
      [for (final section in backupSections) section.id]..sort(),
    );
  }

  /// 恢复备份时把「包含 WebDav 账号」记回来，后续上传沿用。
  Future<void> addBackupSection(BackupSection section) =>
      setBackupSections({...backupSections, section});

  /// 记录一次备份结果（[error] 为空表示成功）。
  Future<void> markBackup({String error = ''}) async {
    lastBackupAt = DateTime.now().millisecondsSinceEpoch;
    lastBackupError = error;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastAt, lastBackupAt);
    if (error.isEmpty) {
      await prefs.remove(_keyLastError);
    } else {
      await prefs.setString(_keyLastError, error);
    }
  }
}
