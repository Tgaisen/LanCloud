import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
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
    final app = AppController();
    addTearDown(app.dispose);
    await app.settings.load();

    await app.setSafDownloadDir(
      const SafDirectory(
        uri: 'content://tree/primary%3ABaiduNetdisk',
        label: '/storage/emulated/0/BaiduNetdisk',
      ),
    );
    expect(app.safDownloadTree, 'content://tree/primary%3ABaiduNetdisk');
    expect(app.settings.downloadDir, isNull);

    // Android 11+ 下选了 Download：公共目录直接按路径写入
    await app.setDownloadDir('/storage/emulated/0/Download');
    expect(app.safDownloadTree, isNull);
    expect(app.settings.downloadDir, '/storage/emulated/0/Download');
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
    final app = AppController();
    addTearDown(app.dispose);
    await app.settings.load();

    await app.setDownloadDir('/storage/emulated/0/Download');
    await app.setSafDownloadDir(
      const SafDirectory(
        uri: 'content://tree/primary%3ABaiduNetdisk',
        label: '/storage/emulated/0/BaiduNetdisk',
      ),
    );
    expect(app.settings.downloadDir, isNull);
    expect(app.safDownloadTree, 'content://tree/primary%3ABaiduNetdisk');
  });
}
