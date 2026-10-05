import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _propfindSample = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/lancloud-backup-20261002-181500.json</d:href>
    <d:propstat><d:prop>
      <d:getcontentlength>2048</d:getcontentlength>
      <d:getlastmodified>Thu, 02 Oct 2026 10:15:00 GMT</d:getlastmodified>
      <d:resourcetype/>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/lancloud-latest.json</d:href>
    <d:propstat><d:prop>
      <d:getcontentlength>1024</d:getcontentlength>
      <d:resourcetype/>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/notes.txt</d:href>
    <d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';

void main() {
  test('PROPFIND 解析：跳过目录、解析大小与修改时间', () {
    final entries = parsePropfind(
      _propfindSample,
      Uri.parse('https://dav.example.com/dav/'),
    );

    expect(entries.map((e) => e.name), [
      'lancloud-backup-20261002-181500.json',
      'lancloud-latest.json',
      'notes.txt',
    ]);
    expect(entries.first.size, 2048);
    expect(entries.first.modified?.toUtc(), DateTime.utc(2026, 10, 2, 10, 15));
  });

  test('WebDAV 地址规范化：补协议与结尾斜杠', () {
    expect(
      WebdavClient.normalizeBase('dav.example.com/blue').toString(),
      'https://dav.example.com/blue/',
    );
    expect(
      WebdavClient.normalizeBase('http://a.com/dav/').toString(),
      'http://a.com/dav/',
    );
  });

  test('备份文件名时间戳格式', () {
    expect(
      BackupService.stamp(DateTime(2026, 10, 2, 18, 15, 5)),
      '20261002-181505',
    );
  });

  test('设置导出后可以原样恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.load();
    await store.setThemeMode('dark');
    await store.setOledBlack(true);
    await store.setRequestInterval(150);
    await store.setHideTopBar(true);
    await store.setHomeFolderOpenMode('drive');

    final exported = store.toJson();

    final target = SettingsStore();
    await target.load();
    await target.applyJson(exported);

    expect(target.themeMode, 'dark');
    expect(target.oledBlack, isTrue);
    expect(target.requestInterval, 150);
    expect(target.hideTopBar, isTrue);
    expect(target.homeFolderOpenMode, 'drive');
  });

  test('恢复设置时忽略未知键，空值表示清除该项', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.load();
    await store.setUploadPath('fileup.php');

    final payload = store.toJson()
      ..['unknown_key'] = 'should-be-ignored'
      ..['upload_path'] = '';
    await store.applyJson(payload);

    // 清空后回落到默认接口路径
    expect(store.uploadPath, 'html5up.php');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('unknown_key'), isNull);
  });
}
