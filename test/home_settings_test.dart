import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('首页目录打开方式默认网盘页，切换后可持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.load();
    expect(store.homeFolderOpenMode, 'drive');

    await store.setHomeFolderOpenMode('page');
    final reloaded = SettingsStore();
    await reloaded.load();
    expect(reloaded.homeFolderOpenMode, 'page');
  });

  test('目录请求记录目标目录并切到网盘视图', () {
    final drive = DriveState();
    final navigation = NavigationState();
    addTearDown(drive.dispose);
    addTearDown(navigation.dispose);
    int? switched;
    navigation.onSwitchTab = (index) => switched = index;

    drive.folderRequest.value = 'folder-1';
    navigation.switchTab(1);

    expect(drive.folderRequest.value, 'folder-1');
    expect(switched, 1);
  });
}
