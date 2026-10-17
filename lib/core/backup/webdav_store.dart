import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_sections.dart';

/// WebDAV 备份配置与自动备份状态（密码单独放安全存储）。
class WebdavStore {
  static const _keyUrl = 'webdav_url';
  static const _keyUser = 'webdav_user';
  static const _keyPath = 'webdav_path';
  static const _keyAuto = 'webdav_auto';
  static const _keyInterval = 'webdav_interval';
  static const _keyBackupSections = 'webdav_backup_sections';
  static const _keyLastAt = 'webdav_last_backup_at';
  static const _keyLastError = 'webdav_last_backup_error';
  static const _securePassword = 'lancloud_webdav_password';
  static const _storage = FlutterSecureStorage();

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

  bool get configured => url.trim().isNotEmpty;

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
    url = prefs.getString(_keyUrl) ?? '';
    username = prefs.getString(_keyUser) ?? '';
    autoBackup = prefs.getBool(_keyAuto) ?? false;
    interval = prefs.getString(_keyInterval) ?? 'daily';
    // 旧配置（已有地址、没有路径项）默认「/」：保持原来的备份位置
    path =
        prefs.getString(_keyPath) ?? (url.trim().isEmpty ? defaultPath : '/');
    backupSections = BackupSection.fromIds(
      prefs.getStringList(_keyBackupSections) ?? const [],
    );
    lastBackupAt = prefs.getInt(_keyLastAt) ?? 0;
    lastBackupError = prefs.getString(_keyLastError) ?? '';
    password = await readPassword();
  }

  /// 读取密码：单独抽出来便于测试替换（测试环境没有安全存储插件）。
  Future<String> readPassword() async {
    try {
      return await _storage.read(key: _securePassword) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> writePassword(String value) async {
    try {
      await _storage.write(key: _securePassword, value: value);
    } catch (_) {}
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
      await prefs.remove(_keyUrl);
    } else {
      await prefs.setString(_keyUrl, this.url);
    }
    if (this.username.isEmpty) {
      await prefs.remove(_keyUser);
    } else {
      await prefs.setString(_keyUser, this.username);
    }
    await prefs.setString(_keyPath, this.path);
    await writePassword(password);
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
