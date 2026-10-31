import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_directory_settings_state.dart';
import 'package:lancloud/core/saf_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('lancloud/saf');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  });

  test('选择 SAF 目录后切到公共目录：清掉授权并释放旧目录', () async {
    final settings = SettingsStore();
    await settings.load();
    final state = DownloadDirectorySettingsState(settings);
    addTearDown(state.revision.dispose);

    await state.selectSafariDirectory(
      const SafDirectory(
        uri: 'content://tree/primary%3ABaiduNetdisk',
        label: '/storage/emulated/0/BaiduNetdisk',
      ),
    );
    expect(state.safariTreeUri, 'content://tree/primary%3ABaiduNetdisk');
    expect(settings.downloadDir, isNull);

    // Android 11+ 下选了 Download：公共目录直接按路径写入
    await state.selectDirectoryPath('/storage/emulated/0/Download');
    expect(state.safariTreeUri, isNull);
    expect(settings.downloadDir, '/storage/emulated/0/Download');
    expect(
      calls.any(
        (c) =>
            c.method == 'releaseDirectory' &&
            c.arguments['uri'] == 'content://tree/primary%3ABaiduNetdisk',
      ),
      isTrue,
      reason: '切回公共目录时要释放旧的 SAF 授权',
    );
  });

  test('选择 SAF 目录：清掉原有的固定路径设置', () async {
    final settings = SettingsStore();
    await settings.load();
    final state = DownloadDirectorySettingsState(settings);
    addTearDown(state.revision.dispose);

    await state.selectDirectoryPath('/storage/emulated/0/Download');
    await state.selectSafariDirectory(
      const SafDirectory(
        uri: 'content://tree/primary%3ABaiduNetdisk',
        label: '/storage/emulated/0/BaiduNetdisk',
      ),
    );
    expect(settings.downloadDir, isNull);
    expect(state.safariTreeUri, 'content://tree/primary%3ABaiduNetdisk');
  });
}
