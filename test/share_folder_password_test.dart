import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/cache_page_settings_state.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/share_folder_page.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

/// 截图里那种「子文件夹自带提取码」：密码不对时服务端回提取码错误，
/// 输对了才返回子文件夹内容。
class _LockedSubfolderClient extends LanzouClient {
  _LockedSubfolderClient() : super(uid: '0');

  final List<String> calls = [];

  @override
  Future<FolderShareDetail> resolveFolderShare(
    String shareUrl, {
    String pwd = '',
  }) async {
    calls.add(pwd);
    if (pwd != 'gmi9') throw const WrongPasswordException();
    return FolderShareDetail(
      name: '作者的其他APP﹣密码gmi9',
      files: [
        ShareFileItem(
          name: 'inner.txt',
          time: '2026-06-22',
          size: '1.1 M',
          url: 'https://example.com/inner',
        ),
      ],
    );
  }
}

FolderShareDetail _parentFolder() => FolderShareDetail(
  name: '测试分享',
  folders: [
    SubFolder(name: '作者的其他APP﹣密码gmi9', url: 'https://example.com/b00q12n52b'),
  ],
);

Future<void> _pumpPage(
  WidgetTester tester, {
  required AppEnvironment environment,
  required LanzouClient client,
}) async {
  final clients = LanzouClientRegistry(factory: (_) => client);
  final transfers = buildTransferManagerForEnvironment(environment);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 700);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transferManagerProvider.overrideWithValue(transfers),
        lanzouClientRegistryProvider.overrideWithValue(clients),
        appDbProvider.overrideWithValue(environment.db),
        cachePageSettingsStateProvider.overrideWithValue(
          environment.cachePageSettings,
        ),
        navigationAppearanceSettingsStateProvider.overrideWithValue(
          environment.navigationAppearanceSettings,
        ),
        navigationStateProvider.overrideWithValue(environment.navigation),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: ShareFolderPage(
          folder: _parentFolder(),
          link: 'https://example.com/b00p',
          pwd: '2vyv',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('子文件夹自带提取码：弹出「此文件夹需要密码」，输对后进入', (tester) async {
    final client = _LockedSubfolderClient();
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await _pumpPage(tester, environment: environment, client: client);

    await tester.tap(find.text('作者的其他APP﹣密码gmi9'));
    await tester.pumpAndSettle();

    // 父文件夹的提取码对这个子文件夹无效 → 不再直接提示「提取码错误」，而是弹输入框
    expect(find.text('此文件夹需要密码'), findsOneWidget);
    expect(find.text('提取码错误'), findsNothing);
    expect(client.calls.first, '2vyv');

    // 输错：弹窗保留，错误标在输入框上
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('此文件夹需要密码'), findsOneWidget);
    expect(find.text('提取码错误'), findsOneWidget);

    // 输对：进入子文件夹，并用这次的提取码打开浏览页
    await tester.enterText(find.byType(TextField), 'gmi9');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('此文件夹需要密码'), findsNothing);
    expect(find.text('inner.txt'), findsOneWidget);
    expect(client.calls.last, 'gmi9');
  });

  testWidgets('子文件夹密码弹窗：留空提交提示请输入提取码，取消不发请求', (tester) async {
    final client = _LockedSubfolderClient();
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    await _pumpPage(tester, environment: environment, client: client);

    await tester.tap(find.text('作者的其他APP﹣密码gmi9'));
    await tester.pumpAndSettle();
    final before = client.calls.length;

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('请输入提取码'), findsOneWidget);
    expect(client.calls.length, before);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('此文件夹需要密码'), findsNothing);
    // 仍停留在原来的分享浏览页
    expect(find.text('测试分享'), findsOneWidget);
  });
}
