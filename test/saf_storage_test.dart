import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/saf_storage.dart';
import 'package:lancloud/core/saved_file.dart';

/// SAF 原生通道（与 SafStorage 里的名字一致）。
const _channel = MethodChannel('lancloud/saf');

const _codec = StandardMethodCodec();

/// 模拟原生侧的 SAF 实现，返回 Dart→原生的调用记录。
List<MethodCall> mockSafNative({
  Map<Object?, Object?>? pickResult,
  Map<Object?, Object?>? exportResult,
  Future<Object?> Function(MethodCall call)? onExport,
}) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'pickDirectory':
            return pickResult;
          case 'exportFile':
            if (onExport != null) return onExport(call);
            return exportResult;
          case 'deleteFile':
          case 'openFile':
            return true;
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

/// 模拟原生 → Dart 的调用（复制进度推送）。
Future<void> emitNativeCall(String method, Object? arguments) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'lancloud/saf',
        _codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pickDirectory：解析 uri / label，透传当前目录，取消返回 null', () async {
    final calls = mockSafNative(
      pickResult: const {
        'uri': 'content://tree/primary%3ABaiduNetdisk',
        'label': '/storage/emulated/0/BaiduNetdisk',
      },
    );
    final dir = await SafStorage.pickDirectory(
      initialUri: 'content://tree/old',
    );
    expect(dir, isNotNull);
    expect(dir!.uri, 'content://tree/primary%3ABaiduNetdisk');
    expect(dir.label, '/storage/emulated/0/BaiduNetdisk');
    expect(calls.single.method, 'pickDirectory');
    expect(calls.single.arguments['initialUri'], 'content://tree/old');

    mockSafNative(pickResult: null);
    expect(await SafStorage.pickDirectory(), isNull);
  });

  test('pickDirectory：公共目录（Download 等）带 directPath，直接写入不走授权', () async {
    mockSafNative(
      pickResult: const {
        'uri': 'content://tree/primary%3ADownload',
        'label': '/storage/emulated/0/Download',
        'path': '/storage/emulated/0/Download',
      },
    );
    final dir = await SafStorage.pickDirectory();
    expect(dir, isNotNull);
    expect(dir!.directPath, '/storage/emulated/0/Download');
  });

  test('export：参数透传，返回目标 URI 与去重后的文件名', () async {
    final calls = mockSafNative(
      exportResult: const {
        'uri': 'content://doc/primary%3ABaiduNetdisk%2Fbq.zip',
        'name': 'bq(1).zip',
      },
    );
    final saved = await SafStorage.export(
      treeUri: 'content://tree/primary%3ABaiduNetdisk',
      sourcePath: '/data/user/0/app/files/.tmp/d1.zip',
      fileName: 'bq.zip',
      mime: 'application/zip',
      jobId: 'd1',
    );
    expect(saved.uri, 'content://doc/primary%3ABaiduNetdisk%2Fbq.zip');
    expect(saved.name, 'bq(1).zip');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['treeUri'], 'content://tree/primary%3ABaiduNetdisk');
    expect(args['sourcePath'], '/data/user/0/app/files/.tmp/d1.zip');
    expect(args['fileName'], 'bq.zip');
    expect(args['mime'], 'application/zip');
    expect(args['jobId'], 'd1');
  });

  test('export：复制进度由原生推送更新到 onProgress', () async {
    final progress = <(int, int)>[];
    mockSafNative(
      onExport: (call) async {
        await emitNativeCall('progress', const {
          'id': 'd1',
          'copied': 5,
          'total': 10,
        });
        await emitNativeCall('progress', const {
          'id': 'd1',
          'copied': 10,
          'total': 10,
        });
        return const {'uri': 'content://doc/x', 'name': 'a.zip'};
      },
    );
    await SafStorage.export(
      treeUri: 'content://tree/x',
      sourcePath: '/tmp/a.zip',
      fileName: 'a.zip',
      mime: 'application/zip',
      jobId: 'd1',
      onProgress: (copied, total) => progress.add((copied, total)),
    );
    expect(progress, [(5, 10), (10, 10)]);
  });

  test('export：授权失效抛 perm_denied，调用方据此提示重新选择目录', () async {
    mockSafNative(
      onExport: (call) => Future.error(
        PlatformException(code: 'perm_denied', message: 'permission denied'),
      ),
    );
    await expectLater(
      SafStorage.export(
        treeUri: 'content://tree/x',
        sourcePath: '/tmp/a.zip',
        fileName: 'a.zip',
        mime: 'application/zip',
      ),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'perm_denied'),
      ),
    );
  });

  test('isContentUri 只认 content:// 前缀', () {
    expect(SafStorage.isContentUri('content://doc/x'), isTrue);
    expect(SafStorage.isContentUri('/storage/emulated/0/a.zip'), isFalse);
    expect(SafStorage.isContentUri(''), isFalse);
  });

  test('mimeForFileName：APK / 压缩包 / 未知类型', () {
    expect(
      mimeForFileName('app.apk'),
      'application/vnd.android.package-archive',
    );
    expect(mimeForFileName('a.zip'), 'application/zip');
    expect(mimeForFileName('noext'), 'application/octet-stream');
    expect(mimeForFileName('a.unknownext'), 'application/octet-stream');
  });
}
