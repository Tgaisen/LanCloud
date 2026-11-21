import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/file_picker_channel.dart';
import 'package:lancloud/core/platform_capabilities.dart';

class _FakeDocumentProviderPicker implements DocumentProviderPicker {
  int calls = 0;

  @override
  Future<List<String>> pickFiles() async {
    calls += 1;
    return ['/cache/native-a.pdf', '/cache/native-b.pdf'];
  }
}

class _FakeSystemFilePicker implements SystemFilePicker {
  final List<String> dialogTitles = [];

  @override
  Future<List<String?>> pickFiles({required String dialogTitle}) async {
    dialogTitles.add(dialogTitle);
    return ['/tmp/a.pdf', null, '', '/tmp/b.pdf'];
  }
}

void main() {
  group('ProviderFilePicker', () {
    test('Android 应该使用文档提供器并保持原生结果', () async {
      final documentProviderPicker = _FakeDocumentProviderPicker();
      final systemFilePicker = _FakeSystemFilePicker();

      final paths = await ProviderFilePicker.pickFiles(
        dialogTitle: '选择文件',
        capabilities: PlatformCapabilities.android,
        documentProviderPicker: documentProviderPicker,
        systemFilePicker: systemFilePicker,
      );

      expect(paths, ['/cache/native-a.pdf', '/cache/native-b.pdf']);
      expect(documentProviderPicker.calls, 1);
      expect(systemFilePicker.dialogTitles, isEmpty);
    });

    test('Windows 与 iOS 应该使用 file_picker 并过滤空路径', () async {
      for (final (:name, :capabilities) in [
        (name: 'Windows', capabilities: PlatformCapabilities.windows),
        (name: 'iOS', capabilities: PlatformCapabilities.ios),
      ]) {
        final documentProviderPicker = _FakeDocumentProviderPicker();
        final systemFilePicker = _FakeSystemFilePicker();

        final paths = await ProviderFilePicker.pickFiles(
          dialogTitle: '选择文件',
          capabilities: capabilities,
          documentProviderPicker: documentProviderPicker,
          systemFilePicker: systemFilePicker,
        );

        expect(paths, ['/tmp/a.pdf', '/tmp/b.pdf'], reason: name);
        expect(documentProviderPicker.calls, 0, reason: name);
        expect(systemFilePicker.dialogTitles, ['选择文件'], reason: name);
      }
    });
  });
}
