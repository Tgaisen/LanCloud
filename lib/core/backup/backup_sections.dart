/// 备份内容分项。
///
/// 本地备份每次由用户在「备份内容」弹窗里勾选（默认都不勾）；
/// WebDAV 备份把勾选结果存进 `WebdavStore`，上传时按它生成备份文件。
enum BackupSection {
  /// 常规：设置项
  settings('settings'),

  /// 常规：收藏夹
  favorites('favorites'),

  /// 账号信息：快速访问
  quick('quick'),

  /// 账号信息：最近使用（已下载标记属于使用记录，跟着它一起）
  recents('recents'),

  /// 敏感信息：Cookie（等同于登录凭据）
  cookies('cookies'),

  /// 敏感信息：WebDav 账号（含密码）
  webdavAccount('webdavAccount');

  const BackupSection(this.id);

  /// 写进备份 JSON / SharedPreferences 的稳定标识。
  final String id;

  /// 勾选前需要身份验证（生物识别 / 锁屏密码）。
  bool get sensitive => this == cookies || this == webdavAccount;

  static BackupSection? fromId(String? id) {
    for (final section in values) {
      if (section.id == id) return section;
    }
    return null;
  }

  /// 解析存储里的标识列表，忽略无法识别的项。
  static Set<BackupSection> fromIds(Iterable<String> ids) =>
      ids.map(fromId).whereType<BackupSection>().toSet();
}
