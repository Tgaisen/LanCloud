import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/transfer_connection_settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LanzouClient.requestInterval = const Duration(milliseconds: 300);
    LanzouClient.apiBase = 'https://pc.woozooo.com';
    LanzouClient.userAgent = '';
    LanzouClient.uploadPath = 'html5up.php';
  });

  tearDown(() {
    LanzouClient.requestInterval = const Duration(milliseconds: 300);
    LanzouClient.apiBase = 'https://pc.woozooo.com';
    LanzouClient.userAgent = '';
    LanzouClient.uploadPath = 'html5up.php';
  });

  test('TransferConnectionSettingsState 读写全部连接与并发字段', () async {
    final settings = SettingsStore();
    final state = TransferConnectionSettingsState(settings);

    expect(settings.downloadConnections, 2);
    expect(settings.skipOversizeUploads, isTrue);
    expect(settings.skipUnsupportedUploads, isTrue);
    expect(settings.autoStartUploads, isTrue);
    await state.setRequestInterval(250);
    await state.setMaxUploads(2);
    await state.setMaxDownloads(4);
    await state.setDownloadConnections(3);
    await state.setApiHost('up');
    await state.setUserAgent('test-agent');
    await state.setUploadPath('fileup.php');
    await state.setSkipOversizeUploads(false);
    await state.setSkipUnsupportedUploads(false);
    await state.setAutoStartUploads(false);

    expect(state.revision.value, 10);
    expect(state.requestInterval, 250);
    expect(state.maxUploads, 2);
    expect(state.maxDownloads, 4);
    expect(state.downloadConnections, 3);
    expect(state.apiHost, 'up');
    expect(state.userAgent, 'test-agent');
    expect(state.uploadPath, 'fileup.php');
    expect(state.skipOversizeUploads, isFalse);
    expect(state.skipUnsupportedUploads, isFalse);
    expect(state.autoStartUploads, isFalse);
    expect(LanzouClient.requestInterval, const Duration(milliseconds: 250));
    expect(LanzouClient.apiBase, 'https://up.woozooo.com');
    expect(LanzouClient.userAgent, 'test-agent');
    expect(LanzouClient.uploadPath, 'fileup.php');
  });

  test('transferConnectionSettingsStateProvider 可被共享实例覆盖', () {
    final state = TransferConnectionSettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [
        transferConnectionSettingsStateProvider.overrideWithValue(state),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(container.read(transferConnectionSettingsStateProvider), state),
      isTrue,
    );
  });
}
