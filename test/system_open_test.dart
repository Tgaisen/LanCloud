import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/system_open.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lancloud/saf');

  test('Android 普通文件路径也交给原生 FileProvider 打开', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return <Object?, Object?>{'ok': true};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final result = await openFileWithSystem(
      '/storage/emulated/0/Download/LanCloud/a.zip',
      name: 'a.zip',
    );

    expect(result.isSuccess, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'openFile');
    expect(
      calls.single.arguments['uri'],
      '/storage/emulated/0/Download/LanCloud/a.zip',
    );
    expect(calls.single.arguments['mime'], 'application/zip');
    expect(calls.single.arguments['displayName'], 'a.zip');
  });
}
