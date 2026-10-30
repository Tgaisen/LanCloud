import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_directory_settings_state.dart';
import 'package:lancloud/core/saf_storage.dart';
import 'package:lancloud/core/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('DownloadDirectorySettingsState 读写普通目录与 SAF 字段', () async {
    final settings = SettingsStore();
    final state = DownloadDirectorySettingsState(settings);

    await state.setDirectoryPath('/downloads/LanCloud');
    await state.setSafariDirectory('content://tree/primary%3ADownload', 'Download');

    expect(state.directoryPath, '/downloads/LanCloud');
    expect(state.safariTreeUri, 'content://tree/primary%3ADownload');
    expect(state.safariLabel, 'Download');

    await state.setDirectoryPath(null);
    await state.setSafariDirectory(null, null);
    expect(state.directoryPath, isNull);
    expect(state.safariTreeUri, isNull);
    expect(state.safariLabel, isNull);
  });

  test('AppController 普通目录与 SAF 设置仍互斥写入', () async {
    final app = AppController(settingsState: SettingsState());
    addTearDown(app.dispose);

    await app.setDownloadDir('/downloads/custom');
    expect(app.settings.downloadDir, '/downloads/custom');
    expect(app.settings.downloadDirTree, isNull);

    await app.setSafDownloadDir(
      const SafDirectory(uri: 'content://tree/x', label: 'X'),
    );
    expect(app.settings.downloadDir, isNull);
    expect(app.settings.downloadDirTree, 'content://tree/x');
    expect(app.settings.downloadDirLabel, 'X');
  });

  test('downloadDirectorySettingsStateProvider 可被共享实例覆盖', () {
    final state = DownloadDirectorySettingsState(SettingsStore());
    final container = ProviderContainer(
      overrides: [
        downloadDirectorySettingsStateProvider.overrideWithValue(state),
      ],
    );
    addTearDown(container.dispose);

    expect(
      identical(
        container.read(downloadDirectorySettingsStateProvider),
        state,
      ),
      isTrue,
    );
  });
}
