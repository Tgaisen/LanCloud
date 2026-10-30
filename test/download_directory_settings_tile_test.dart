import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/download_directory_settings_state.dart';
import 'package:lancloud/core/download_path_service.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/download_directory_settings_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDownloadPathService implements DownloadPathService {
  const _FakeDownloadPathService(this.path);

  final String path;

  @override
  Future<String> defaultDownloadDirPath() async => path;
}

Future<void> _pump(
  WidgetTester tester, {
  required DownloadDirectorySettingsState state,
  required String defaultPath,
  Future<String?> Function()? pickDirectoryPath,
}) async {
  final container = ProviderContainer(
    overrides: [
      downloadDirectorySettingsStateProvider.overrideWithValue(state),
      downloadPathServiceProvider.overrideWithValue(
        _FakeDownloadPathService(defaultPath),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: DownloadDirectorySettingsTile(
            android: false,
            pickDirectoryPath: pickDirectoryPath,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('普通下载目录不依赖 AppController，并局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore();
    final state = DownloadDirectorySettingsState(store);
    await _pump(
      tester,
      state: state,
      defaultPath: '/default/LanCloud',
      pickDirectoryPath: () async => '/downloads/new',
    );

    expect(find.text('默认（/default/LanCloud）'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '下载目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更改'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.downloadDir, '/downloads/new');
    expect(state.revision.value, 1);
    expect(find.text('/downloads/new'), findsOneWidget);
  });

  testWidgets('恢复默认目录会释放旧 SAF 授权并局部刷新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SettingsStore()
      ..downloadDirTree = 'content://tree/old'
      ..downloadDirLabel = 'Old';
    final released = <String>[];
    final state = DownloadDirectorySettingsState(
      store,
      releaseSaf: (uri) async => released.add(uri),
    );
    await _pump(
      tester,
      state: state,
      defaultPath: '/default/LanCloud',
    );

    await tester.tap(find.widgetWithText(ListTile, '下载目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();

    expect(store.downloadDirTree, isNull);
    expect(released, ['content://tree/old']);
    expect(state.revision.value, 1);
    expect(find.text('默认（/default/LanCloud）'), findsOneWidget);
  });
}
