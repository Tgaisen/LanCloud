import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/backup/backup_service.dart';
import 'package:lancloud/core/backup/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 外部脚本生成的「只含收藏夹」备份：只要求 `app` / `format` / `tables`，
/// 收藏行里 kind / name / ref（可选 pwd、title、size、created_at）就够。
const _scriptBackup =
    '{"includeCookies":false,"createdAt":1791288947864,"sections":["favorites"],'
    '"tables":{"favorites":['
    '{"size":"","id":1,"title":"","kind":"shareFolder","pwd":"Gcf2","sharer":"","created_at":1791288947864,"name":"我的工具","ref":"https://wwx.lanzoux.com/b01hxwx9g"},'
    '{"size":"","id":2,"title":"","kind":"shareFolder","pwd":"","sharer":"","created_at":1791288947864,"name":"SmartisanOS内置壁纸包","ref":"https://yxxdz.lanzoue.com/b0vynkxg"},'
    '{"size":"","id":6,"title":"周杰伦演唱会","kind":"shareFile","pwd":"","sharer":"","created_at":1791288947864,"name":"周杰伦 - 错过的烟火.FLAC","ref":"https://yxxdz.lanzoue.com/ijVwf3lehorc"}'
    ']},"app":"lancloud","format":2}';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('外部脚本生成的收藏夹备份可以恢复（含分享文件夹密码）', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController();
    final service = BackupService(app);

    expect(BackupService.containsFavorites(_scriptBackup), isTrue);
    await service.restoreFromString(_scriptBackup);

    final favorites = await app.db.favorites();
    expect(
      favorites.map((f) => f.name),
      containsAll(<String>['我的工具', 'SmartisanOS内置壁纸包']),
    );
    final folder = favorites.firstWhere((f) => f.name == '我的工具');
    expect(folder.kind, 'shareFolder');
    expect(folder.pwd, 'Gcf2');
  });

  test('缺少 app 字段（比如写成 appname）会被判成不是本应用备份', () async {
    SharedPreferences.setMockInitialValues({});
    final service = BackupService(AppController());
    final wrong = _scriptBackup.replaceFirst(
      '"app":"lancloud"',
      '"appname":"lancloud"',
    );

    await expectLater(
      service.restoreFromString(wrong),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('LanCloud'),
        ),
      ),
    );
  });
}
