import 'package:dio/dio.dart' show CancelToken;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/account_state.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/transfers_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_test_support.dart' show buildTransferManagerForEnvironment;
export 'transfer_test_support.dart' show buildTransferManagerForEnvironment;

Widget transferTestHost({
  required AppEnvironment app,
  required TransferManager manager,
  required Widget child,
  PlatformCapabilities capabilities = PlatformCapabilities.android,
}) {
  return ProviderScope(
    overrides: [
      transferManagerProvider.overrideWithValue(manager),
      accountStateProvider.overrideWithValue(app.accountState),
      listHomeSettingsStateProvider.overrideWithValue(app.listHomeSettings),
      navigationAppearanceSettingsStateProvider.overrideWithValue(
        app.navigationAppearanceSettings,
      ),
      navigationStateProvider.overrideWithValue(app.navigation),
      platformCapabilitiesProvider.overrideWithValue(capabilities),
    ],
    child: child,
  );
}

TransferTask task(
  String id,
  String name, {
  required TransferStatus status,
  TransferKind kind = TransferKind.upload,
  String accountUid = '',
  String folderId = '',
  String folderName = '',
}) {
  return TransferTask(
    id: id,
    kind: kind,
    name: name,
    accountUid: accountUid,
    folderId: folderId,
    folderName: folderName,
    localFilePath: '/tmp/$name',
  )..status = status;
}

class FolderPickerClient extends LanzouClient {
  FolderPickerClient() : super(uid: 'u1');

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId, {
    CancelToken? cancelToken,
  }) async => (
    folders: const <LzFolder>[],
    path: folderId == '-1'
        ? const <PathNode>[]
        : <PathNode>[PathNode(id: folderId, name: '当前目录')],
  );
}

Future<(AppEnvironment, TransferManager)> host(WidgetTester tester) async {
  final app = AppEnvironment();
  final manager = buildTransferManagerForEnvironment(app);
  manager.tasks.addAll([
    task('t1', 'a.zip', status: TransferStatus.failed),
    task('t2', 'b.zip', status: TransferStatus.failed),
    task('t3', 'c.zip', status: TransferStatus.done),
  ]);
  await tester.pumpWidget(
    transferTestHost(
      app: app,
      manager: manager,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const TransfersPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('上传').hitTestable());
  await tester.pumpAndSettle();
  return (app, manager);
}

Future<(AppEnvironment, TransferManager)> hostWithTasks(
  WidgetTester tester,
  List<TransferTask> tasks, {
  LanzouClient? uploadClient,
  PlatformCapabilities capabilities = PlatformCapabilities.android,
}) async {
  final app = AppEnvironment();
  final manager = buildTransferManagerForEnvironment(app);
  manager.tasks.addAll(tasks);
  await tester.pumpWidget(
    transferTestHost(
      app: app,
      manager: manager,
      capabilities: capabilities,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: TransfersPage(
          activeUploadClient: uploadClient == null ? null : () => uploadClient,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.tap(find.text('上传').hitTestable());
  await pumpTransferUi(tester);
  return (app, manager);
}

bool retryEnabled(WidgetTester tester) {
  final action = tester.widget<BatchAction>(
    // 图标按钮没有可见文字：标签就是 tooltip，按它定位
    find.ancestor(of: find.byTooltip('重试'), matching: find.byType(BatchAction)),
  );
  return action.onPressed != null;
}

/// 多选顶栏常驻在树里（靠透明度切换显示），用它判断多选是否真的打开。
double selectionBarOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('transfers-selection-appbar')),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

/// 把传输页作为独立页面（二级路由）打开，用于验证返回行为。
Future<AppEnvironment> pushTransfers(WidgetTester tester) async {
  final app = AppEnvironment();
  final manager = buildTransferManagerForEnvironment(app);
  manager.tasks.addAll([task('t1', 'a.zip', status: TransferStatus.failed)]);
  await tester.pumpWidget(
    transferTestHost(
      app: app,
      manager: manager,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    // 独立路由形态（非底栏视图）：返回键 / 多选条按此分支
                    builder: (_) => const TransfersPage(),
                  ),
                ),
                child: const Text('打开传输'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开传输'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('上传').hitTestable());
  await tester.pumpAndSettle();
  return app;
}

int selectedTransferTab(WidgetTester tester) => tester
    .widget<M3eConnectedButtonGroup<int>>(
      find.byType(M3eConnectedButtonGroup<int>),
    )
    .selected;

/// 运行中的波浪进度条会持续调度帧，不能用 pumpAndSettle 等待它“结束”。
Future<void> pumpTransferUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// 打开某一行（按文件名定位）的 ⋯ 菜单。
Future<void> openTransferRowMenu(WidgetTester tester, String name) async {
  final row = find.ancestor(
    of: find.text(name),
    matching: find.byType(Md3ListItem),
  );
  await tester.tap(find.descendant(of: row, matching: find.byTooltip('更多操作')));
  await tester.pumpAndSettle();
}

/// 菜单里的项（按显示顺序）。多选操作栏里也有「重试 / 删除」同文案的按钮，
/// 所以这里只认菜单自己的行。
List<String> transferMenuLabels(WidgetTester tester) => tester
    .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
    .map((row) => row.label)
    .toList();

Finder transferMenuItem(String label) =>
    find.descendant(of: find.byType(M3eMenuRow), matching: find.text(label));
