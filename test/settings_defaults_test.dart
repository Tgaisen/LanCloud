import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/app_info.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首次启动：识别剪贴板链接默认关闭（避免系统弹剪贴板读取提醒）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.load();
    expect(store.clipboardLinkPrompt, isFalse);
  });

  test('用户手动打开后，重启仍然保持开启', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'clipboard_link_prompt': true,
    });
    final store = SettingsStore();
    await store.load();
    expect(store.clipboardLinkPrompt, isTrue);
  });

  test('SAF 下载目录（tree URI + 展示名）可持久化与清除', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.setDownloadDirTree(
      'content://tree/primary%3ABaiduNetdisk',
      '/storage/emulated/0/BaiduNetdisk',
    );

    final reloaded = SettingsStore();
    await reloaded.load();
    expect(reloaded.downloadDirTree, 'content://tree/primary%3ABaiduNetdisk');
    expect(reloaded.downloadDirLabel, '/storage/emulated/0/BaiduNetdisk');

    await reloaded.setDownloadDirTree(null, null);
    final cleared = SettingsStore();
    await cleared.load();
    expect(cleared.downloadDirTree, isNull);
    expect(cleared.downloadDirLabel, isNull);
  });

  test('更新通道默认跟随安装版本类型，自动检查默认开启', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.load();
    expect(
      store.updateChannel,
      isPrereleaseVersion(appVersion) ? 'beta' : 'stable',
    );
    expect(store.updateAutoCheck, isTrue);
  });

  test('更新通道与自动检查开关可持久化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    await store.load();
    await store.setUpdateChannel('stable');
    await store.setUpdateAutoCheck(false);

    final reloaded = SettingsStore();
    await reloaded.load();
    expect(reloaded.updateChannel, 'stable');
    expect(reloaded.updateAutoCheck, isFalse);
  });
}
