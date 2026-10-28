import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/shared_downloads_storage.dart';

const _channel = MethodChannel('lancloud/shared_downloads');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    SharedDownloadsStorage.resetCacheForTesting();
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'isSupported' => true,
            'defaultDirectory' => '/storage/emulated/0/Download/LanCloud',
            'saveFile' => <String, Object?>{
              'uri': 'content://media/external/downloads/42',
              'name': 'archive.zip',
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    SharedDownloadsStorage.resetCacheForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('读取支持状态和默认公共目录路径', () async {
    expect(await SharedDownloadsStorage.isSupported(), isTrue);
    expect(
      await SharedDownloadsStorage.defaultDirectoryPath(),
      '/storage/emulated/0/Download/LanCloud',
    );
    expect(calls.map((call) => call.method), [
      'isSupported',
      'defaultDirectory',
    ]);
  });

  test('写入后返回 MediaStore URI，并传递源文件与 MIME', () async {
    final saved = await SharedDownloadsStorage.save(
      sourcePath: '/tmp/archive.zip',
      fileName: 'archive.zip',
      mime: 'application/zip',
      jobId: 'job-1',
    );

    expect(saved.uri, 'content://media/external/downloads/42');
    expect(saved.name, 'archive.zip');
    final saveCall = calls.singleWhere((call) => call.method == 'saveFile');
    expect(saveCall.arguments, {
      'sourcePath': '/tmp/archive.zip',
      'fileName': 'archive.zip',
      'mime': 'application/zip',
      'jobId': 'job-1',
    });
  });
}
