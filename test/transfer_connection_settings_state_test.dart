import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/settings_state.dart';
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

    await state.setRequestInterval(250);
    await state.setMaxUploads(2);
    await state.setMaxDownloads(4);
    await state.setApiHost('up');
    await state.setUserAgent('test-agent');
    await state.setUploadPath('fileup.php');

    expect(state.requestInterval, 250);
    expect(state.maxUploads, 2);
    expect(state.maxDownloads, 4);
    expect(state.apiHost, 'up');
    expect(state.userAgent, 'test-agent');
    expect(state.uploadPath, 'fileup.php');
  });

  test('AppController 旧 API 继续同步 LanzouClient 静态配置', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);

    await app.setRequestInterval(180);
    await app.setApiHost('up');
    await app.setUserAgent('LanCloud-test');
    await app.setUploadPath('fileup.php');
    await app.setMaxUploads(2);
    await app.setMaxDownloads(4);

    expect(
      LanzouClient.requestInterval,
      const Duration(milliseconds: 180),
    );
    expect(LanzouClient.apiBase, 'https://up.woozooo.com');
    expect(LanzouClient.userAgent, 'LanCloud-test');
    expect(LanzouClient.uploadPath, 'fileup.php');
    expect(app.settings.maxUploads, 2);
    expect(app.settings.maxDownloads, 4);
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
      identical(
        container.read(transferConnectionSettingsStateProvider),
        state,
      ),
      isTrue,
    );
  });
}
