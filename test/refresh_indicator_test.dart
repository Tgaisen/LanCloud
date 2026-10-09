import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/app_scroll.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

/// MD3E 下拉刷新（M3ePullToRefresh，overlay 版）：
/// 内容位移归滚动 physics（iOS 橡皮筋原样），指示器是固定在上边缘的纯视觉层，
/// 进度只读滚动通知。这里守住触发/取消/禁用/收回四条底线。
Widget _harness({
  required Future<void> Function() onRefresh,
  bool enabled = true,
  double triggerDistance = 40,
  Duration minimumDisplayDuration = Duration.zero,
  ScrollPhysics physics = AppScrollBehavior.physics,
}) => MaterialApp(
  scrollBehavior: const AppScrollBehavior(),
  home: Scaffold(
    body: M3ePullToRefresh(
      enabled: enabled,
      triggerDistance: triggerDistance,
      minimumDisplayDuration: minimumDisplayDuration,
      onRefresh: onRefresh,
      semanticsLabel: '刷新',
      child: CustomScrollView(
        physics: physics,
        slivers: const [
          SliverToBoxAdapter(
            child: SizedBox(height: 200, child: Center(child: Text('内容'))),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 900)),
        ],
      ),
    ),
  ),
);

Future<void> pullDown(WidgetTester tester, double distance) async {
  await tester.drag(find.text('内容'), Offset(0, distance), touchSlopY: 0);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('渲染子内容', (tester) async {
    await tester.pumpWidget(_harness(onRefresh: () async {}));
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('Bouncing 原样保留：下拉时内容被物理层拉下去，指示器浮在上面', (tester) async {
    await tester.pumpWidget(_harness(onRefresh: () async {}));
    final double restingY = tester.getTopLeft(find.text('内容')).dy;

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('内容')),
    );
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();

    // 内容确实被 physics 拉下去了（回弹没被替换掉）
    expect(tester.getTopLeft(find.text('内容')).dy, greaterThan(restingY));
    // 指示器出现在内容之上（固定 overlay，不参与布局）
    expect(find.byType(M3EContainedLoadingIndicator), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('过阈值松手触发刷新，指示器保持到刷新完成', (tester) async {
    final completer = Completer<void>();
    var refreshed = 0;
    await tester.pumpWidget(
      _harness(
        onRefresh: () {
          refreshed += 1;
          return completer.future;
        },
      ),
    );

    await pullDown(tester, 300);
    expect(refreshed, 1);
    expect(find.byType(M3EContainedLoadingIndicator), findsOneWidget);

    completer.complete();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('轻拉（未过阈值）松手不触发，指示器收回', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      _harness(triggerDistance: 80, onRefresh: () async => refreshed += 1),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('内容')),
    );
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.up();
    // 收回是 spring 动画：先 pump 一帧建立 ticker 起点，再等它收敛。
    await tester.pumpAndSettle();

    expect(refreshed, 0);
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('拉过阈值再往回拉回阈值内松手：取消刷新', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(_harness(onRefresh: () async => refreshed += 1));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('内容')),
    );
    await gesture.moveBy(const Offset(0, 260));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -260));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    expect(refreshed, 0);
  });

  testWidgets('enabled=false 时不响应下拉刷新', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      _harness(enabled: false, onRefresh: () async => refreshed += 1),
    );

    await pullDown(tester, 300);
    expect(refreshed, 0);
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('clamping 物理（Android 默认）也能触发', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      _harness(
        physics: const AlwaysScrollableScrollPhysics(),
        onRefresh: () async => refreshed += 1,
      ),
    );

    await pullDown(tester, 160);
    expect(refreshed, 1);
  });

  testWidgets('用力甩回顶部后不卡住、不留残留指示器', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: M3ePullToRefresh(
            onRefresh: () async {},
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverList.builder(
                  itemCount: 60,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 60, child: Text('第 $i 行')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -800),
      touchSlopY: 0,
    );
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.position.pixels, greaterThan(0));

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 900),
      4000,
    );
    await tester.pumpAndSettle();

    expect(scroll.position.pixels, 0);
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -200),
      touchSlopY: 0,
    );
    await tester.pump();
    expect(scroll.position.pixels, greaterThan(0), reason: '甩回顶部后应能继续滚动');
  });

  testWidgets('起手不在顶部：一路拖到顶部并继续下拉也能触发（anywhere）', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: M3ePullToRefresh(
            minimumDisplayDuration: Duration.zero,
            onRefresh: () async => refreshed += 1,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverList.builder(
                  itemCount: 40,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 60, child: Text('第 $i 行')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 先滚到列表中间（起手显然不在顶部）
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -600),
      touchSlopY: 0,
    );
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.position.pixels, greaterThan(0));

    // 手指按住往下拖：先回到顶部，越过顶部后接管并出小球
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 700));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();

    expect(find.byType(M3EContainedLoadingIndicator), findsOneWidget);
    expect(scroll.position.pixels, lessThanOrEqualTo(0), reason: '已越过顶部（回弹）');

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, 1, reason: '过阈值松手应触发刷新');
  });
}
