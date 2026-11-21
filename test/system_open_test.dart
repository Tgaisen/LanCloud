import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/file_open_result.dart';
import 'package:lancloud/core/system_open.dart';

class _FakeSystemOpenAdapter implements SystemOpenAdapter {
  final List<String> opened = [];
  final List<String> revealed = [];

  @override
  Future<FileOpenResult> openFile(String path, {String? name}) async {
    opened.add(path);
    return const FileOpenResult.success();
  }

  @override
  Future<bool> revealInExplorer(String path) async {
    revealed.add(path);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lancloud/saf');

  test('系统文件打开按 adapter 分流并保留 Android FileProvider 参数', () async {
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

    final gateway = _FakeSystemOpenAdapter();
    expect(
      await openFileWithSystem('/tmp/a.zip', name: 'a.zip', adapter: gateway),
      isA<FileOpenResult>().having((result) => result.isSuccess, '成功', true),
    );
    expect(await revealInExplorer('/tmp/a.zip', adapter: gateway), isTrue);
    expect(gateway.opened, ['/tmp/a.zip']);
    expect(gateway.revealed, ['/tmp/a.zip']);

    final temp = await Directory.systemTemp.createTemp('lancloud_system_open_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}a.zip');
    await file.writeAsString('test');
    final processCalls = <String>[];
    final windows = WindowsSystemOpenAdapter(
      startProcess: (executable, arguments) async {
        processCalls.add('$executable ${arguments.join(' ')}');
      },
    );

    expect((await windows.openFile(file.path)).isSuccess, isTrue);
    expect(await windows.revealInExplorer(file.path), isTrue);
    expect(processCalls, [
      'explorer.exe ${file.path}',
      'explorer.exe /select,${file.path}',
    ]);
  });
}
