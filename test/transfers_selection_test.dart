import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:lancloud/ui/transfers_page.dart';

import 'support/transfer_page_test_support.dart';

void main() {
  testWidgets('独立页面：多选时返回只退出多选，不退出页面', (tester) async {
    final app = await pushTransfers(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isFalse);
    expect(find.byType(TransfersPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TransfersPage), findsNothing);
  });

  testWidgets('点击上传条目不做任何反应：长按才进入多选', (tester) async {
    final (app, _) = await host(tester);

    // 上传条目点不开，点击不做任何反应，也不会进入多选
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isFalse);
    expect(selectionBarOpacity(tester), 0);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(selectionBarOpacity(tester), 1);
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(app.navigation.selectionMode, isTrue);
  });

  // 回归：播报必须挂在「真正进入多选」上。多选条在页面里常驻（透明度切换），
  // 之前把播报放进多选条 initState，导致从首页打开传输页/收藏就误读「进入多选」，
  // 而网盘页真正进入多选反而没提示。
  testWidgets('页面打开不播报「进入多选」，长按进入时才播报一次', (tester) async {
    final announcements = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          final event = message as Map<dynamic, dynamic>;
          if (event['type'] == 'announce') {
            announcements.add(
              (event['data'] as Map<dynamic, dynamic>)['message'] as String,
            );
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    // 打开传输页（多选条已经建在树里）不该播报
    final app = await pushTransfers(tester);
    // 等过播报的延迟窗口：页面构建本身不能产生任何播报
    await tester.pump(const Duration(milliseconds: 400));
    expect(announcements, isEmpty);

    // 长按进入多选：播报一次
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(announcements, ['进入多选']);

    // 已在多选里继续长按其它条目不再重复播报
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(announcements, ['进入多选']);

    // 退出多选后再收尾，避免页面 dispose 时去动已销毁的控制器
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    app.dispose();
  });

  // 行内操作（取消 / ⋯）多选时只隐藏不改变布局：条目高度不变。
  testWidgets('多选隐藏行内操作但保留占位：条目高度不变', (tester) async {
    final (app, _) = await host(tester);
    final item = find.ancestor(
      of: find.text('a.zip'),
      matching: find.byType(Md3ListItem),
    );
    final height = tester.getSize(item).height;
    final more = find.descendant(of: item, matching: find.byTooltip('更多操作'));
    expect(more, findsOneWidget);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isTrue);
    expect(tester.getSize(item).height, height);
    expect(
      tester
          .widget<HideKeepingSpace>(
            find.ancestor(of: more, matching: find.byType(HideKeepingSpace)),
          )
          .hidden,
      isTrue,
    );

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(tester.getSize(item).height, height);
    expect(more, findsOneWidget);
    app.dispose();
  });

  testWidgets('进入多选后各分栏操作变为选择，并追加选中该栏全部任务', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 1600);
    addTearDown(tester.view.reset);
    final (app, _) = await hostWithTasks(tester, [
      task('u1', 'pending.txt', status: TransferStatus.pending),
      task('u2', 'running.txt', status: TransferStatus.running),
      task('u3', 'skipped.txt', status: TransferStatus.skipped),
      task('u4', 'failed.txt', status: TransferStatus.failed),
      task('u5', 'done.txt', status: TransferStatus.done),
    ]);

    await tester.longPress(find.text('pending.txt'));
    await pumpTransferUi(tester);

    for (final key in [
      'transfers-select-pending',
      'transfers-select-active',
      'transfers-select-skipped',
      'transfers-select-failed',
      'transfers-select-finished',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('选择'), findsNWidgets(5));
    expect(find.byKey(const ValueKey('transfers-clear-pending')), findsNothing);
    expect(find.byKey(const ValueKey('transfers-clear-skipped')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transfers-select-failed')));
    await pumpTransferUi(tester);
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transfers-select-finished')));
    await pumpTransferUi(tester);
    expect(find.text('已选择 3 项'), findsOneWidget);

    await tester.tap(find.byTooltip('退出多选'));
    await pumpTransferUi(tester);
    expect(
      find.byKey(const ValueKey('transfers-clear-finished')),
      findsOneWidget,
    );
    app.dispose();
  });

  testWidgets('非紧凑分栏的上下留白不受右侧操作影响', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionHeader(
            title: '进行中',
            count: 1,
            actions: [TextButton(onPressed: () {}, child: const Text('全部暂停'))],
          ),
        ),
      ),
    );

    final header = tester.widget<SectionHeader>(find.byType(SectionHeader));
    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(SectionHeader),
            matching: find.byType(Padding),
          )
          .first,
    );

    expect(header.compact, isFalse);
    expect(padding.padding, const EdgeInsets.fromLTRB(4, 16, 4, 8));
  });

  testWidgets('分栏标题密度跟随实际宽度而不是平台', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final (:width, :compact) in [
      (width: 639.0, compact: true),
      (width: 640.0, compact: false),
    ]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Text('${useCompactSectionHeader(context)}'),
          ),
        ),
      );
      expect(find.text('$compact'), findsOneWidget);
    }
  });

  // 多选期间切换上传 / 下载：不禁用按钮组，切换后自动退出多选。
  testWidgets('多选时切换上传 / 下载会退出多选', (tester) async {
    await host(tester);
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(selectionBarOpacity(tester), 1);

    // 下载在前；按钮组内部会重复构建 label（用于测量/动画），按位置点左侧。
    final group = tester.getRect(find.byType(M3eConnectedButtonGroup<int>));
    expect(
      tester
          .widget<M3eConnectedButtonGroup<int>>(
            find.byType(M3eConnectedButtonGroup<int>),
          )
          .values,
      const [1, 0],
    );
    await tester.tapAt(
      Offset(group.left + group.width * 0.25, group.center.dy),
    );
    await tester.pumpAndSettle();

    expect(selectionBarOpacity(tester), 0, reason: '切换 tab 后应退出多选');
    expect(find.text('暂无下载任务'), findsOneWidget);
  });

  // 取消最后一个选中项 → 自动退出多选（不再停在「已选择 0 项」）。
  testWidgets('选中数归零自动退出多选', (tester) async {
    await host(tester);
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(selectionBarOpacity(tester), 1);

    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();

    expect(selectionBarOpacity(tester), 0);
  });

  // 顶栏只保留多选入口；分栏右侧负责各自的清空操作。
  testWidgets('顶栏多选按钮点击进入多选并播报', (tester) async {
    final announcements = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          final event = message as Map<dynamic, dynamic>;
          if (event['type'] == 'announce') {
            announcements.add(
              (event['data'] as Map<dynamic, dynamic>)['message'] as String,
            );
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    final (app, _) = await host(tester);

    final multiSelect = find.byTooltip('多选');
    expect(multiSelect, findsOneWidget);
    expect(find.byTooltip('清除已完成'), findsNothing);

    await tester.tap(multiSelect);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(app.navigation.selectionMode, isTrue);
    // 先用顶栏进多选（未选中任何条目），也要有提示
    expect(announcements, ['进入多选']);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isFalse);
    app.dispose();
  });

  testWidgets('长按进入多选：显示已选数量，重试仅对失败项可用', (tester) async {
    final (app, manager) = await host(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfers-selection-appbar')),
      findsOneWidget,
    );
    expect(find.text('已选择 1 项'), findsOneWidget);
    // 选中的是失败项 → 重试可用
    expect(retryEnabled(tester), isTrue);

    // 再加选一个已完成项，计数更新
    await tester.tap(find.text('c.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(retryEnabled(tester), isTrue);

    // 只选已完成项时重试不可用
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(retryEnabled(tester), isFalse);

    // 退出多选
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(app.navigation.selectionMode, isFalse);
    expect(manager.tasks.length, 3);
    app.dispose();
  });

  testWidgets('多选删除：确认后移除选中记录', (tester) async {
    final (app, manager) = await host(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('c.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    // 确认弹窗
    expect(find.text('删除传输记录'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    // 批量删除不逐条播删除动画：确认后立即移除记录，不需要等动画
    await tester.pump();
    await tester.pump();
    expect(manager.tasks.map((t) => t.id).toList(), ['t2']);
    await tester.pumpAndSettle();

    expect(manager.tasks.map((t) => t.id).toList(), ['t2']);
    // 列表一次刷新到位：被删的两条都不再渲染
    expect(find.text('a.zip'), findsNothing);
    expect(find.text('c.zip'), findsNothing);
    expect(find.text('b.zip'), findsOneWidget);
    expect(app.navigation.selectionMode, isFalse);
    app.dispose();
  });
}
