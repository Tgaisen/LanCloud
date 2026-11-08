import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/lanzou_client_registry.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/share_file_sheet.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

/// 解析一定失败的假客户端：测试里不联网；错误信息不含「不存在 / 取消」，
/// 所以不会被判成失效（失效会让整张表的入口置灰，测不了点击行为）。
class _NoNetClient extends LanzouClient {
  _NoNetClient() : super(uid: '0');

  @override
  Future<ShareFileDetails> fetchFileShareDetails(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    throw const LanzouException('网络异常');
  }

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    throw const LanzouException('网络异常');
  }
}

class _FakeApp {
  _FakeApp([LanzouClient? publicClient])
    : _public = publicClient ?? _NoNetClient();

  final AppEnvironment environment = AppEnvironment();
  final LanzouClient _public;

  LanzouClient get sheetClient => _public;

  void dispose() => environment.dispose();
}

/// 详情加载失败，但点击下载后的直链解析挂起，等测试放行。
class _GateSecondPublic extends LanzouClient {
  _GateSecondPublic() : super(uid: '0');

  final Completer<DirectFile> gate = Completer<DirectFile>();

  @override
  Future<ShareFileDetails> fetchFileShareDetails(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    throw const LanzouException('网络异常');
  }

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) => gate.future;
}

/// 返回指定大小的假客户端：模拟文件页把大小解析错（如历史 bug 的 22）。
class _SizeClient extends LanzouClient {
  _SizeClient(this.size) : super(uid: '0');

  final String size;

  @override
  Future<ShareFileDetails> fetchFileShareDetails(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async =>
      ShareFileDetails(size: size, time: '2026-06-22', requiresPassword: true);

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

  int detailCalls = 0;
  int resolveCalls = 0;

  @override
  Future<ShareFileDetails> fetchFileShareDetails(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    detailCalls += 1;
    return const ShareFileDetails(name: 'a.zip', size: '1 M', desc: '这是文件简介');
  }

  @override
  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    resolveCalls += 1;
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
  String time = '',
  String sharer = '',
  bool asModal = false,
}) async {
  final transfers =
      manager ?? buildTransferManagerForEnvironment(app.environment);
  final clients = LanzouClientRegistry(factory: (_) => app.sheetClient);
  addTearDown(app.dispose);
  final sheet = ShareFileInfoSheet(
    name: 'a.zip',
    url: 'https://example.com/abcdef',
    pwd: '',
    size: size,
    time: time,
    sharer: sharer,
    invalid: invalid,
  );
  final home = asModal
      ? Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-share-file-sheet'),
                onPressed: () => showAppSheet<void>(context, child: sheet),
                child: const Text('打开属性'),
              ),
            ),
          ),
        )
      : Scaffold(body: sheet);
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (asModal) {
    await tester.tap(find.byKey(const ValueKey('open-share-file-sheet')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  testWidgets('分享文件属性弹窗：简介、快捷按钮与详情列表分层展示', (tester) async {
    final client = _DescClient();
    await _pumpSheet(tester, _FakeApp(client), time: '2 天前', sharer: '测试分享者');
    expect(client.detailCalls, 1);
    expect(client.resolveCalls, 0);
    expect(find.text('这是文件简介'), findsOneWidget);

    expect(find.byType(M3EToggleButton), findsNWidgets(4));
    for (final tooltip in ['下载', '复制链接', '显示二维码', '收藏']) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
    expect(find.text('类型'), findsOneWidget);
    expect(find.text('ZIP 文件'), findsOneWidget);
    expect(find.text('大小'), findsOneWidget);
    expect(find.text('1 MB'), findsOneWidget);
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('2 天前'), findsOneWidget);
    expect(find.text('分享者'), findsOneWidget);
    expect(find.text('测试分享者'), findsOneWidget);
    expect(find.text('访问密码'), findsOneWidget);
    expect(find.text('未启用'), findsOneWidget);
  });

  testWidgets('分享文件属性弹窗：大小以列表值为准，不被文件页解析值覆盖', (tester) async {
    // 列表给的 31.5 M 是文件夹接口的真实大小；文件页解析出的 22 是错的
    await _pumpSheet(tester, _FakeApp(_SizeClient('22')), size: '31.5 M');

    // 密码页取不到真实名称时沿用调用方给的名称，不能显示 URL 末段。
    expect(find.text('a.zip'), findsOneWidget);
    expect(find.text('abcdef'), findsNothing);
    expect(find.textContaining('31.5 MB'), findsOneWidget);
    expect(find.textContaining('22.0 MB'), findsNothing);
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('2026-06-22'), findsOneWidget);
    expect(find.text('访问密码'), findsOneWidget);
    expect(find.text('已启用'), findsOneWidget);
  });

  testWidgets('分享文件属性弹窗：复制和二维码支持分享链接 / 下载直链且保留属性页', (tester) async {
    final client = _DescClient();
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpSheet(tester, _FakeApp(client), asModal: true);
    expect(client.detailCalls, 1);
    expect(client.resolveCalls, 0);

    expect(find.text('打开链接'), findsNothing);
    expect(find.byTooltip('下载'), findsOneWidget);
    expect(find.byTooltip('复制链接'), findsOneWidget);
    expect(find.byTooltip('显示二维码'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('复制链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('复制分享链接'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('复制下载直链'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('复制分享链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboard, hasLength(1));
    expect(
      '${(clipboard.single.arguments as Map)['text']}',
      'https://example.com/abcdef',
    );
    expect(client.resolveCalls, 0);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(find.byTooltip('复制链接'), findsOneWidget);

    await tester.tap(find.byTooltip('复制链接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('复制下载直链'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboard, hasLength(2));
    expect(
      '${(clipboard.last.arguments as Map)['text']}',
      'https://example.com/a',
    );
    expect(client.resolveCalls, 1);
    expect(find.byType(M3EBottomSheet), findsOneWidget);

    await tester.tap(find.byTooltip('显示二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('分享链接二维码'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(M3eMenuRow),
        matching: find.text('下载直链二维码'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('分享链接二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(client.resolveCalls, 1);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('关闭')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    expect(find.byTooltip('显示二维码'), findsOneWidget);

    await tester.tap(find.byTooltip('显示二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('下载直链二维码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(M3EBottomSheet), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('关闭')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(M3EBottomSheet), findsOneWidget);

    // 等复制轻提示的定时器结束。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('分享文件属性弹窗：已加入下载时是「已加入下载」+ 进度环，点击弹二级菜单', (tester) async {
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
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

    // 下载中：按钮提示「下载中」+ 确定态进度环（40%）
    expect(find.byTooltip('下载中'), findsOneWidget);
    expect(find.byTooltip('下载'), findsNothing);
    final ring = tester.widget<M3eCircularProgressIndicator>(
      find.byType(M3eCircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.4, 0.001));

    // 点它：二级菜单按状态给可用项（进行中：暂停与取消下载可点）
    await tester.tap(find.byTooltip('下载中'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final rows = tester
        .widgetList<M3eMenuRow>(find.byType(M3eMenuRow))
        .toList();
    expect(rows.map((r) => r.label).toList(), [
      '打开',
      '分享',
      '暂停下载',
      '取消下载',
      '删除记录与文件',
      '重新下载',
    ]);
    expect(rows[0].enabled, isFalse);
    expect(rows[1].enabled, isFalse);
    expect(rows[2].enabled, isTrue);
    expect(rows[3].enabled, isTrue);
    // 还没落盘：删除记录与文件不可用
    expect(rows[4].enabled, isFalse);
    expect(rows[5].enabled, isFalse);

    // 取消下载：标记消失，入口回到「下载」
    await tester.tap(
      find.descendant(of: find.byType(M3eMenuRow), matching: find.text('取消下载')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('下载'), findsOneWidget);
    expect(find.byTooltip('已加入下载'), findsNothing);
    expect(manager.downloadMarkOf('https://example.com/abcdef'), isNull);
  });

  testWidgets('分享文件属性弹窗：各下载状态的文案与图标', (tester) async {
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
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
    expect(find.byTooltip('等待中'), findsOneWidget);
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
    expect(find.byTooltip('下载中'), findsOneWidget);

    // 正在保存：文案切换，进度环继续显示复制进度
    task.status = TransferStatus.saving;
    task.received = 75;
    manager.marksRevision.value += 1;
    await tester.pump();
    expect(find.byTooltip('正在保存'), findsOneWidget);
    expect(
      tester
          .widget<M3eCircularProgressIndicator>(
            find.byType(M3eCircularProgressIndicator),
          )
          .value,
      closeTo(0.75, 0.001),
    );

    // 已完成：勾图标、「已加入下载」、无环
    task.status = TransferStatus.done;
    task.savedPath = '/tmp/a.zip';
    manager.marksRevision.value += 1;
    await tester.pump();
    expect(find.byTooltip('已加入下载'), findsOneWidget);
    expect(find.byIcon(Icons.download_done), findsOneWidget);
    expect(find.byType(M3eCircularProgressIndicator), findsNothing);

    // 下载失败：「下载失败」+ 下载关闭图标、无环
    task.status = TransferStatus.failed;
    manager.marksRevision.value += 1;
    await tester.pump();
    expect(find.byTooltip('下载失败'), findsOneWidget);
    expect(find.byIcon(Icons.file_download_off), findsOneWidget);
    expect(find.byType(M3eCircularProgressIndicator), findsNothing);
  });

  testWidgets('分享文件属性弹窗：解析中显示不确定态环，解析失败恢复原状', (tester) async {
    final gate = _GateSecondPublic();
    final app = _FakeApp(gate);
    await _pumpSheet(
      tester,
      app,
      manager: buildTransferManagerForEnvironment(app.environment),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ShareFileInfoSheet)),
    );

    await tester.tap(find.byTooltip('下载'));
    await tester.pump();
    // 解析中：不确定态环 + 「解析中」（文案取 l10n，避免写死后被改文案带崩）
    expect(find.byTooltip(l10n.resolving), findsOneWidget);
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
    expect(find.byTooltip('下载'), findsOneWidget);
    expect(find.byTooltip(l10n.resolving), findsNothing);
  });

  testWidgets('二级菜单：这条任务的下载状态变更时自动收起', (tester) async {
    final app = _FakeApp();
    final manager = buildTransferManagerForEnvironment(app.environment);
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

    await tester.tap(find.byTooltip('下载中'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(M3eMenuRow), findsNWidgets(6));

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
    final manager = buildTransferManagerForEnvironment(app.environment);
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

    await tester.tap(find.byTooltip('下载失败'));
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
    expect(find.byTooltip(l10n.resolving), findsOneWidget);
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
    expect(find.byTooltip('下载'), findsOneWidget);
  });
}
