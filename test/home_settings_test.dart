import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('首页目录打开方式默认新页面，切换后可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.load();
    expect(store.homeFolderOpenMode, 'page');

    await store.setHomeFolderOpenMode('drive');
    final reloaded = SettingsStore();
    await reloaded.load();
    expect(reloaded.homeFolderOpenMode, 'drive');
  });

  test('openFolderInDrive 记录目标目录并请求切到网盘视图', () {
    final app = AppController();
    int? switched;
    app.onSwitchTab = (index) => switched = index;

    app.openFolderInDrive('folder-1');

    expect(app.driveFolderRequest.value, 'folder-1');
    expect(switched, 1);
    app.dispose();
  });
}
