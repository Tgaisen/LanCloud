import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_sections.dart';

/// WebDAV 备份配置与自动备份状态（密码单独放安全存储）。
class WebdavStore {
  static const _keyUrl = 'webdav_url';
  static const _keyUser = 'webdav_user';
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

  /// daily | weekly
  String interval = 'daily';

  /// WebDAV 备份内容（只影响 WebDAV 上传，与本地备份的每次勾选互不影响）。
  Set<BackupSection> backupSections = <BackupSection>{};

  int lastBackupAt = 0;
  String lastBackupError = '';

  bool get configured => url.trim().isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    url = prefs.getString(_keyUrl) ?? '';
    username = prefs.getString(_keyUser) ?? '';
    autoBackup = prefs.getBool(_keyAuto) ?? false;
    interval = prefs.getString(_keyInterval) ?? 'daily';
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
  }) async {
    this.url = url.trim();
    this.username = username.trim();
    this.password = password;
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
