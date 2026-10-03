import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
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
}
