import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/system_share.dart';

class _RecordingGateway implements SystemShareGateway {
  final List<String> calls = [];

  @override
  Future<bool> shareText(String text, {String subject = ''}) async {
    calls.add('text:$text:$subject');
    return true;
  }

  @override
  Future<bool> shareFile(
    String path, {
    String subject = '',
    String mime = 'application/json',
  }) async {
    calls.add('file:$path:$subject:$mime');
    return true;
  }

  @override
  Future<bool> shareFiles(
    Iterable<String> paths, {
    String subject = '',
    String? mime,
  }) async {
    calls.add('files:${paths.join(',')}:$subject:$mime');
    return true;
  }
}

void main() {
  group('SystemShareGateway', () {
    test('应该按平台能力选择原生、桌面降级或 unsupported', () {
      expect(
        systemShareGatewayFor(PlatformCapabilities.android),
        isA<NativeSystemShareGateway>(),
      );
      expect(
        systemShareGatewayFor(PlatformCapabilities.windows),
        isA<DesktopSystemShareGateway>(),
      );
      expect(
        systemShareGatewayFor(PlatformCapabilities.macOS),
        isA<DesktopSystemShareGateway>(),
      );
      expect(
        systemShareGatewayFor(PlatformCapabilities.linux),
        isA<DesktopSystemShareGateway>(),
      );
      expect(
        systemShareGatewayFor(PlatformCapabilities.ios),
        isA<UnsupportedSystemShareGateway>(),
      );
      expect(
        systemShareGatewayFor(PlatformCapabilities.unsupported),
        isA<UnsupportedSystemShareGateway>(),
      );
    });

    test('原生实现应该转发文本、单文件和多文件参数', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final gateway = NativeSystemShareGateway(
        invoke: (method, arguments) async {
          calls.add((method, arguments));
          return true;
        },
      );

      expect(await gateway.shareText('文本', subject: '主题'), isTrue);
      expect(
        await gateway.shareFile('/a.json', mime: 'application/json'),
        isTrue,
      );
      expect(
        await gateway.shareFiles(
          ['/a.json', '', '/b.json'],
          subject: '批量',
          mime: 'application/zip',
        ),
        isTrue,
      );
      expect(await gateway.shareFiles(['/single.json']), isTrue);
      expect(await gateway.shareFiles(const []), isFalse);

      expect(
        [for (final call in calls) call.$1],
        ['shareText', 'shareFile', 'shareFiles', 'shareFile'],
      );
      expect(calls[0].$2, {'text': '文本', 'subject': '主题'});
      expect(calls[1].$2, {
        'path': '/a.json',
        'subject': '',
        'mime': 'application/json',
      });
      expect(calls[2].$2, {
        'paths': ['/a.json', '/b.json'],
        'subject': '批量',
        'mime': 'application/zip',
      });
      expect(calls[3].$2, {
        'path': '/single.json',
        'subject': '',
        'mime': 'application/octet-stream',
      });
    });

    test('桌面实现应该复制文本并定位首个文件', () async {
      final clipboard = <String>[];
      final revealed = <String>[];
      final gateway = DesktopSystemShareGateway(
        writeClipboard: (text) async => clipboard.add(text),
        reveal: (path) async {
          revealed.add(path);
          return true;
        },
      );

      expect(await gateway.shareText('携带 Cookie'), isTrue);
      expect(await gateway.shareFile('/a.json'), isTrue);
      expect(await gateway.shareFiles(['', '/b.zip', '/c.zip']), isTrue);
      expect(await gateway.shareFiles(const []), isFalse);

      expect(clipboard, ['携带 Cookie']);
      expect(revealed, ['/a.json', '/b.zip']);
    });

    test('unsupported 实现应该全部返回 false', () async {
      const gateway = UnsupportedSystemShareGateway();

      expect(await gateway.shareText('文本'), isFalse);
      expect(await gateway.shareFile('/a.json'), isFalse);
      expect(await gateway.shareFiles(['/a.json']), isFalse);
    });

    test('SystemShare 静态入口应该使用注入的 gateway', () async {
      final gateway = _RecordingGateway();

      expect(
        await SystemShare.shareText('文本', subject: '主题', gateway: gateway),
        isTrue,
      );
      expect(await SystemShare.shareFile('/a.json', gateway: gateway), isTrue);
      expect(
        await SystemShare.shareFiles(['/a.json', '/b.json'], gateway: gateway),
        isTrue,
      );
      expect(gateway.calls, [
        'text:文本:主题',
        'file:/a.json::application/json',
        'files:/a.json,/b.json::null',
      ]);
    });
  });
}
