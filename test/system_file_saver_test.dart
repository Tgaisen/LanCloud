import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/system_file_saver.dart';

class _FakeSafFileSaveGateway implements SafFileSaveGateway {
  int calls = 0;

  @override
  Future<String?> save({
    required String sourcePath,
    required String fileName,
    required String mime,
  }) async {
    calls += 1;
    return 'native-saved.pdf';
  }
}

class _FakeSystemFileSaveDialog implements SystemFileSaveDialog {
  final List<String> dialogTitles = [];
  String? result = 'renamed.pdf';

  @override
  Future<String?> save({
    required String sourcePath,
    required String fileName,
    required String dialogTitle,
    required String mime,
  }) async {
    dialogTitles.add(dialogTitle);
    return result;
  }
}

void main() {
  group('SystemFileSaver', () {
    test('Android 应该使用 SAF 另存为路径', () async {
      final saf = _FakeSafFileSaveGateway();
      final system = _FakeSystemFileSaveDialog();

      final saved = await SystemFileSaver.save(
        sourcePath: '/tmp/source.pdf',
        fileName: 'source.pdf',
        dialogTitle: '导出文件',
        mime: 'application/pdf',
        capabilities: PlatformCapabilities.android,
        safFileSaveGateway: saf,
        systemFileSaveDialog: system,
      );

      expect(saved, 'native-saved.pdf');
      expect(saf.calls, 1);
      expect(system.dialogTitles, isEmpty);
    });

    test('Windows 与 iOS 应该使用通用另存为对话框', () async {
      for (final (:name, :capabilities) in [
        (name: 'Windows', capabilities: PlatformCapabilities.windows),
        (name: 'iOS', capabilities: PlatformCapabilities.ios),
      ]) {
        final saf = _FakeSafFileSaveGateway();
        final system = _FakeSystemFileSaveDialog();

        final saved = await SystemFileSaver.save(
          sourcePath: '/tmp/source.pdf',
          fileName: 'source.pdf',
          dialogTitle: '导出文件',
          mime: 'application/pdf',
          capabilities: capabilities,
          safFileSaveGateway: saf,
          systemFileSaveDialog: system,
        );

        expect(saved, 'renamed.pdf', reason: name);
        expect(saf.calls, 0, reason: name);
        expect(system.dialogTitles, ['导出文件'], reason: name);
      }
    });

    test('用户取消时应该返回 null', () async {
      final saf = _FakeSafFileSaveGateway();
      final system = _FakeSystemFileSaveDialog()..result = null;

      final saved = await SystemFileSaver.save(
        sourcePath: '/tmp/source.pdf',
        fileName: 'source.pdf',
        dialogTitle: '导出文件',
        mime: 'application/pdf',
        capabilities: PlatformCapabilities.ios,
        safFileSaveGateway: saf,
        systemFileSaveDialog: system,
      );

      expect(saved, isNull);
    });

    test('能力关闭时应该 fail closed', () async {
      final saf = _FakeSafFileSaveGateway();
      final system = _FakeSystemFileSaveDialog();

      final saved = await SystemFileSaver.save(
        sourcePath: '/tmp/source.pdf',
        fileName: 'source.pdf',
        dialogTitle: '导出文件',
        mime: 'application/pdf',
        capabilities: PlatformCapabilities.linux,
        safFileSaveGateway: saf,
        systemFileSaveDialog: system,
      );

      expect(saved, isNull);
      expect(saf.calls, 0);
      expect(system.dialogTitles, isEmpty);
    });
  });
}
