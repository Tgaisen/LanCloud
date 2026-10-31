import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_directory_settings_state.dart';
import 'package:lancloud/core/saf_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('DownloadDirectorySettingsState 读写普通目录与 SAF 字段', () async {
    final settings = SettingsStore();
    final released = <String>[];
    final state = DownloadDirectorySettingsState(
      settings,
      releaseSaf: (uri) async => released.add(uri),
    );

    await state.selectDirectoryPath('/downloads/LanCloud');
    await state.selectSafariDirectory(
      const SafDirectory(
        uri: 'content://tree/primary%3ADownload',
        label: 'Download',
      ),
    );

    expect(state.revision.value, 2);
    expect(state.directoryPath, isNull);
    expect(state.safariTreeUri, 'content://tree/primary%3ADownload');
    expect(state.safariLabel, 'Download');

    await state.selectDirectoryPath(null);
    expect(state.directoryPath, isNull);
    expect(state.safariTreeUri, isNull);
    expect(state.safariLabel, isNull);
    expect(released, ['content://tree/primary%3ADownload']);
    expect(state.revision.value, 3);
  });

  test('普通目录与 SAF 设置互斥写入', () async {
    final settings = SettingsStore();
    final state = DownloadDirectorySettingsState(
      settings,
      releaseSaf: (_) async {},
    );

    await state.selectDirectoryPath('/downloads/custom');
    expect(settings.downloadDir, '/downloads/custom');
    expect(settings.downloadDirTree, isNull);

    await state.selectSafariDirectory(
      const SafDirectory(uri: 'content://tree/x', label: 'X'),
    );
    expect(settings.downloadDir, isNull);
    expect(settings.downloadDirTree, 'content://tree/x');
    expect(settings.downloadDirLabel, 'X');
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
