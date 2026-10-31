import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/share_file_sheet.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_dependencies_test.dart' show buildTransferManager;

/// 解析一定失败的假客户端：测试里不联网；错误信息不含「不存在 / 取消」，
/// 所以不会被判成失效（失效会让整张表的入口置灰，测不了点击行为）。
class _NoNetClient extends LanzouClient {
  _NoNetClient() : super(uid: '0');

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    throw const LanzouException('网络异常');
  }
}

class _FakeApp extends AppController {
  _FakeApp([LanzouClient? publicClient])
    : _public = publicClient ?? _NoNetClient();

  final LanzouClient _public;

  LanzouClient get sheetClient => _public;
}

/// 第一次解析（弹窗加载）立刻失败，之后的解析（点击下载）挂起等测试放行。
class _GateSecondPublic extends LanzouClient {
  _GateSecondPublic() : super(uid: '0');

  final Completer<DirectFile> gate = Completer<DirectFile>();
  int calls = 0;

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) {
    calls += 1;
    if (calls == 1) return Future.error(const LanzouException('网络异常'));
    return gate.future;
  }
}

/// 返回指定大小的假客户端：模拟文件页把大小解析错（如历史 bug 的 22）。
class _SizeClient extends LanzouClient {
  _SizeClient(this.size) : super(uid: '0');

  final String size;

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    return DirectFile(name: 'a.zip', url: 'https://example.com/a', size: size);
  }
}

/// 文件页带简介：验证信息卡会把简介显示出来。
class _DescClient extends LanzouClient {
  _DescClient() : super(uid: '0');

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    return DirectFile(
      name: 'a.zip',
      url: 'https://example.com/a',
      size: '1 M',
      desc: '这是文件简介',
    );
  }
}

Future<void> _pumpSheet(
  WidgetTester tester,
  _FakeApp app, {
  TransferManager? manager,
  bool invalid = false,
  String size = '1 MB',
}) async {
  final transfers = manager ?? buildTransferManager(app);
  final clients = LanzouClientRegistry(factory: (_) => app.sheetClient);
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transferManagerProvider.overrideWithValue(transfers),
        lanzouClientRegistryProvider.overrideWithValue(clients),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: ShareFileInfoSheet(
            name: 'a.zip',
            url: 'https://example.com/abcdef',
            pwd: '',
            size: size,
            invalid: invalid,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('分享文件属性弹窗：文件页有简介时显示在信息卡里', (tester) async {
    await _pumpSheet(tester, _FakeApp(_DescClient()));
    expect(find.text('这是文件简介'), findsOneWidget);
  });

  testWidgets('分享文件属性弹窗：大小以列表值为准，不被文件页解析值覆盖', (tester) async {
    // 列表给的 31.5 M 是文件夹接口的真实大小；文件页解析出的 22 是错的
    await _pumpSheet(tester, _FakeApp(_SizeClient('22')), size: '31.5 M');

    expect(find.textContaining('31.5 MB'), findsOneWidget);
    expect(find.textContaining('22.0 MB'), findsNothing);
  });

  // 分享文件夹浏览页里点文件弹出的这张表就是「项目菜单」：只留下载 / 复制链接 /
  // 二维码 / 收藏，「打开链接」按需求去掉（浏览器的入口在别处）。
  testWidgets('分享文件属性弹窗：没有「打开链接」，其余入口都在', (tester) async {
    await _pumpSheet(tester, _FakeApp(), invalid: true);

    expect(find.text('打开链接'), findsNothing);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('显示二维码'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets('分享文件属性弹窗：已加入下载时是「已下载」+ 进度环，点击弹二级菜单', (tester) async {
    final app = _FakeApp();
    final manager = buildTransferManager(app);
    manager.tasks.add(
      TransferTask(
          id: 'd1',
          kind: TransferKind.download,
          name: 'a.zip',
          accountUid: '',
          referer: 'https://example.com/abcdef',
        )
        ..status = TransferStatus.running
        ..total = 100
        ..received = 40,
    );
    await _pumpSheet(tester, app, manager: manager);

    // 下载中：文本「下载中」+ 确定态进度环（40%）
    expect(find.text('下载中'), findsOneWidget);
    expect(find.text('下载'), findsNothing);
    final ring = tester.widget<M3eCircularProgressIndicator>(
      find.byType(M3eCircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.4, 0.001));

    // 点它：二级菜单按状态给可用项（进行中：只有「取消下载」可点）
    await tester.tap(find.text('下载中'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final rows = tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .toList();
    expect(rows.map((r) => r.label).toList(), [
      '打开',
      '分享',
      '取消下载',
      '删除记录与文件',
      '重新下载',
    ]);
    expect(rows[0].enabled, isFalse);
    expect(rows[1].enabled, isFalse);
    expect(rows[2].enabled, isTrue);
    // 还没落盘：删除记录与文件不可用
    expect(rows[3].enabled, isFalse);
    expect(rows[4].enabled, isFalse);

    // 取消下载：标记消失，入口回到「下载」
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('取消下载')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('已下载'), findsNothing);
    expect(manager.downloadMarkOf('https://example.com/abcdef'), isNull);
  });

  testWidgets('分享文件属性弹窗：各下载状态的文案与图标', (tester) async {
    final app = _FakeApp();
    final manager = buildTransferManager(app);
    final task =
        TransferTask(
            id: 'd1',
            kind: TransferKind.download,
            name: 'a.zip',
            accountUid: '',
            referer: 'https://example.com/abcdef',
          )
          ..status = TransferStatus.queued
          ..total = 100;
    // 先不开态渲染（排队中的不确定态环会一直转，pumpAndSettle 等不到静止）
    await _pumpSheet(tester, app, manager: manager);
    manager.tasks.add(task);
    manager.marksRevision.value += 1;
    await tester.pump();

    // 等待中：不确定态环
    expect(find.text('等待中'), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      isNull,
    );

    // 下载中：确定态环
    task.status = TransferStatus.running;
    task.received = 40;
    manager.marksRevision.value += 1;
    await tester.pump();
    expect(find.text('下载中'), findsOneWidget);

    // 已完成：勾图标、「已下载」、无环
    task.status = TransferStatus.done;
    task.savedPath = '/tmp/a.zip';
    manager.marksRevision.value += 1;
    await tester.pump();
    expect(find.text('已下载'), findsOneWidget);
    expect(find.byIcon(Icons.download_done), findsOneWidget);
    expect(find.byType(M3eCircularProgressIndicator), findsNothing);

    // 下载失败：「下载失败」+ 下载关闭图标、无环
    task.status = TransferStatus.failed;
    manager.marksRevision.value += 1;
    await tester.pump();
    expect(find.text('下载失败'), findsOneWidget);
    expect(find.byIcon(Icons.file_download_off), findsOneWidget);
    expect(find.byType(M3eCircularProgressIndicator), findsNothing);
  });

  testWidgets('分享文件属性弹窗：解析中显示不确定态环，解析失败恢复原状', (tester) async {
    final gate = _GateSecondPublic();
    final app = _FakeApp(gate);
    await _pumpSheet(tester, app, manager: buildTransferManager(app));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ShareFileInfoSheet)),
    );

    await tester.tap(find.text('下载'));
    await tester.pump();
    // 解析中：不确定态环 + 「解析中」（文案取 l10n，避免写死后被改文案带崩）
    expect(find.text(l10n.resolving), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      isNull,
    );

    // 解析失败：回到「下载」原状
    gate.gate.completeError(const LanzouException('网络异常'));
    await tester.pump();
    await tester.pump();
    expect(find.text('下载'), findsOneWidget);
    expect(find.text(l10n.resolving), findsNothing);
  });

  testWidgets('二级菜单：这条任务的下载状态变更时自动收起', (tester) async {
    final app = _FakeApp();
    final manager = buildTransferManager(app);
    final task =
        TransferTask(
            id: 'd1',
            kind: TransferKind.download,
            name: 'a.zip',
            accountUid: '',
            referer: 'https://example.com/abcdef',
          )
          ..status = TransferStatus.running
          ..total = 100
          ..received = 30;
    manager.tasks.add(task);
    await _pumpSheet(tester, app, manager: manager);

    await tester.tap(find.text('下载中'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(M3eMenuRow), findsNWidgets(5));

    // 这条任务完成（状态变了）：菜单自动收起，别让用户对着旧选项点
    task.status = TransferStatus.done;
    task.savedPath = '/tmp/a.zip';
    manager.marksRevision.value += 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(M3eMenuRow), findsNothing);
  });

  testWidgets('分享文件属性弹窗：点「重新下载」立刻进入解析中状态', (tester) async {
    final gate = _GateSecondPublic();
    final app = _FakeApp(gate);
    final manager = buildTransferManager(app);
    manager.tasks.add(
      TransferTask(
        id: 'd1',
        kind: TransferKind.download,
        name: 'a.zip',
        accountUid: '',
        referer: 'https://example.com/abcdef',
      )..status = TransferStatus.failed,
    );
    await _pumpSheet(tester, app, manager: manager);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ShareFileInfoSheet)),
    );

    await tester.tap(find.text('下载失败'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('重新下载')),
    );
    // 点击 → 菜单收起（post-frame 回调）→ 选择回调里删旧任务并开始解析
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 旧任务已删、新任务还没入队：立刻进入「解析中」+ 不确定态环
    expect(manager.tasks, isEmpty);
    expect(find.text(l10n.resolving), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      isNull,
    );

    // 解析失败：回到「下载」原状
    gate.gate.completeError(const LanzouException('网络异常'));
    await tester.pump();
    await tester.pump();
    expect(find.text('下载'), findsOneWidget);
  });
}
