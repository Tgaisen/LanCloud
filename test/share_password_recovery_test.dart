import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/core/data/app_db_provider.dart';
import 'package:lancloud/core/drive_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/favorites_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'transfer_dependencies_test.dart' show buildTransferManagerForEnvironment;

/// 收藏里存的是旧提取码：只有新提取码能解析成功。
class _StalePwdClient extends LanzouClient {
  _StalePwdClient() : super(uid: '0');

  @override
  Future<FolderShareDetail> resolveFolderShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    if (pwd != 'newpass') throw const WrongPasswordException();
    return FolderShareDetail(
      name: '收藏的文件夹',
      files: [
        ShareFileItem(
          name: 'inside.txt',
          time: '2026-10-01',
          size: '1 M',
          url: 'https://example.com/in',
        ),
      ],
    );
  }

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    if (pwd != 'newpass') throw const WrongPasswordException();
    return DirectFile(
      // 服务端的名称和收藏里的旧名称不一样：验证信息同步
      name: 'fav-renamed.txt',
      url: 'https://example.com/d',
      size: '2 M',
      sharer: '分享者甲',
    );
  }
}

/// 模拟网络层的非业务异常：没有 LanzouException 文案，也必须给用户提示。
class _BrokenFolderClient extends LanzouClient {
  _BrokenFolderClient() : super(uid: '0');

  @override
  Future<FolderShareDetail> resolveFolderShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    throw Exception('网络连接中断');
  }
}

/// 第一次（旧密码）报提取码错误，第二次（新密码）挂起：
/// 用来验证 downloadShareFile 会用新密码重试，又不会真的入队下载。
class _PwdThenHangClient extends LanzouClient {
  _PwdThenHangClient() : super(uid: '0');

  final List<String> calls = [];
  final Completer<DirectFile> gate = Completer<DirectFile>();

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) {
    calls.add(pwd);
    if (pwd != 'newpass') return Future.error(const WrongPasswordException());
    return gate.future;
  }
}

class _FakeApp {
  _FakeApp(this._client);

  final AppEnvironment environment = AppEnvironment();
  final LanzouClient _client;

  LanzouClient get dialogClient => _client;
  AccountState get accountState => environment.accountState;
  AppDb get db => environment.db;
  DriveState get drive => environment.drive;
  NavigationAppearanceSettingsState get navigationAppearanceSettings =>
      environment.navigationAppearanceSettings;
  NavigationState get navigation => environment.navigation;

  void dispose() => environment.dispose();
}

Future<void> _pumpFavorites(
  WidgetTester tester,
  _FakeApp app, {
  required Finder item,
}) async {
  final transfers = buildTransferManagerForEnvironment(app.environment);
  final clients = LanzouClientRegistry(
    factory: (_) => app.dialogClient,
  );
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 720);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transferManagerProvider.overrideWithValue(transfers),
        lanzouClientRegistryProvider.overrideWithValue(clients),
        accountStateProvider.overrideWithValue(app.accountState),
        appDbProvider.overrideWithValue(app.db),
        driveStateProvider.overrideWithValue(app.drive),
        navigationAppearanceSettingsStateProvider.overrideWithValue(
          app.navigationAppearanceSettings,
        ),
        navigationStateProvider.overrideWithValue(app.navigation),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const FavoritesPage(),
      ),
    ),
  );
  // 收藏来自真实 sqlite：让真实的异步查询在 fake-async 测试里也跑完
  await _until(tester, item);
}

/// 交替推进真实事件循环与帧：sqflite 的回包是真实异步，单靠 pump 不会到。
Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  int tries = 40,
}) async {
  for (var i = 0; i < tries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待 $finder 超时');
}

/// 等数据库写入落库：属性弹窗是「先刷 UI、再异步写收藏」，直接查会拿到旧值。
Future<FavoriteItem> _eventuallyFavorite(
  WidgetTester tester,
  _FakeApp app,
  String ref, {
  required bool Function(FavoriteItem item) done,
}) async {
  late FavoriteItem last;
  for (var i = 0; i < 80; i++) {
    final all = await tester.runAsync(() => app.db.favorites());
    last = all!.firstWhere((f) => f.ref == ref);
    if (done(last)) return last;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  return last;
}

void main() {
  setUpAll(() {
    // 收藏数据要真的落库：测试环境用 ffi 的 sqlite
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('收藏文件夹：提取码失效时弹「此文件夹需要密码」，验证后写回收藏', (tester) async {
    final app = _FakeApp(_StalePwdClient());
    addTearDown(app.dispose);
    final ref =
        'https://example.com/b-fav-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(
      () => app.db.addFavorite(
        kind: 'shareFolder',
        name: '收藏的文件夹',
        ref: ref,
        pwd: 'oldpass',
      ),
    );
    await _pumpFavorites(tester, app, item: find.text('收藏的文件夹'));

    await tester.tap(find.text('收藏的文件夹'));
    await _until(tester, find.text('此文件夹需要密码'));

    // 收藏里的旧提取码不对 → 弹专用密码框，而不是直接报错
    expect(find.text('此文件夹需要密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'newpass');
    await tester.tap(find.text('确定'));
    await _until(tester, find.text('inside.txt'));

    // 进入文件夹浏览页
    expect(find.text('inside.txt'), findsOneWidget);
    // 新提取码已同步写回收藏
    final saved = await _eventuallyFavorite(
      tester,
      app,
      ref,
      done: (f) => f.pwd == 'newpass',
    );
    expect(saved.pwd, 'newpass');
  });

  testWidgets('收藏文件夹：打开时非业务异常也显示解析失败提示', (tester) async {
    final app = _FakeApp(_BrokenFolderClient());
    addTearDown(app.dispose);
    final ref =
        'https://example.com/b-broken-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(
      () => app.db.addFavorite(kind: 'shareFolder', name: '打不开的文件夹', ref: ref),
    );
    await _pumpFavorites(tester, app, item: find.text('打不开的文件夹'));

    await tester.tap(find.text('打不开的文件夹'));
    await _until(tester, find.textContaining('解析失败：'));

    expect(find.textContaining('网络连接中断'), findsOneWidget);
    expect(find.text('解析中'), findsNothing);
  });

  testWidgets('收藏信息编辑：分享链接为空时显示统一 error state', (tester) async {
    final app = _FakeApp(_StalePwdClient());
    addTearDown(app.dispose);
    final ref =
        'https://example.com/i-edit-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(
      () => app.db.addFavorite(kind: 'shareFile', name: '待编辑.txt', ref: ref),
    );
    await _pumpFavorites(tester, app, item: find.text('待编辑.txt'));

    final favoriteTile = find.ancestor(
      of: find.text('待编辑.txt'),
      matching: find.byType(Md3ListItem),
    );
    await tester.tap(
      find.descendant(of: favoriteTile, matching: find.byTooltip('更多操作')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改信息'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final linkField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(linkField.decoration!.errorText, '请输入分享链接');
    expect(find.text('请输入分享链接'), findsOneWidget);
    expect(find.byIcon(app_icons.Icons.error), findsOneWidget);
  });

  testWidgets('收藏文件：提取码失效时弹「此文件需要密码」，验证后写回收藏并显示分享者', (tester) async {
    final app = _FakeApp(_StalePwdClient());
    addTearDown(app.dispose);
    final ref =
        'https://example.com/i-fav-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(
      () => app.db.addFavorite(
        kind: 'shareFile',
        name: 'fav.txt',
        ref: ref,
        pwd: 'oldpass',
      ),
    );
    await _pumpFavorites(tester, app, item: find.text('fav.txt'));

    await tester.tap(find.text('fav.txt'));
    await _until(tester, find.text('此文件需要密码'));
    expect(find.text('此文件需要密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'newpass');
    await tester.tap(find.text('确定'));
    await _until(tester, find.textContaining('分享者 分享者甲'));

    expect(find.text('此文件需要密码'), findsNothing);
    // 解析出的新名称也显示在信息卡上
    expect(find.text('fav-renamed.txt'), findsWidgets);
    // 信息卡：大小 · 分享者（收藏里没有日期，所以只有两段）
    expect(find.text('2.0 MB · 分享者 分享者甲'), findsOneWidget);
    final saved = await _eventuallyFavorite(
      tester,
      app,
      ref,
      done: (f) =>
          f.pwd == 'newpass' &&
          f.name == 'fav-renamed.txt' &&
          f.sharer == '分享者甲' &&
          f.size == '2 M',
    );
    expect(saved.pwd, 'newpass');
    // 名称与分享者同步写回收藏
    expect(saved.name, 'fav-renamed.txt');
    expect(saved.sharer, '分享者甲');
    // 收藏时缺失的 size 也补上了（列表副标题会显示 2.0 MB）
    expect(saved.size, '2 M');
  });

  testWidgets('downloadShareFile：提取码错误时用 askPassword 的新密码重试', (tester) async {
    final client = _PwdThenHangClient();
    final app = _FakeApp(client);
    addTearDown(app.dispose);
    final manager = buildTransferManagerForEnvironment(app.environment);
    final clients = LanzouClientRegistry(factory: (_) => app.dialogClient);
    var asked = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferManagerProvider.overrideWithValue(manager),
          lanzouClientRegistryProvider.overrideWithValue(clients),
          navigationAppearanceSettingsStateProvider.overrideWithValue(
            app.navigationAppearanceSettings,
          ),
          navigationStateProvider.overrideWithValue(app.navigation),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => downloadShareFile(
                  context,
                  url: 'https://example.com/i1',
                  pwd: 'oldpass',
                  showLoading: false,
                  askPassword: () async {
                    asked += 1;
                    return 'newpass';
                  },
                ),
                child: const Text('下载'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('下载'));
    await tester.pump();
    await tester.pump();

    expect(asked, 1);
    expect(client.calls, ['oldpass', 'newpass']);
    // 第二次解析挂起（不复用 gate），没有真的入队
    expect(manager.tasks, isEmpty);
  });
}
