import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/app_scroll.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:material_ui/material_ui.dart';

/// MD3E 下拉刷新（M3ePullToRefresh）：拖拽、阈值、回弹都在组件内部，
/// 这里守住的是「能不能触发刷新」与「禁用时是否完全不响应」两条底线。
Widget host({required bool enabled, Future<void> Function()? onRefresh}) =>
    MaterialApp(
      home: Scaffold(
        body: M3ePullToRefresh(
          gesture: PullToRefreshGesture(),
          enabled: enabled,
          edgeOffset: 56,
          semanticsLabel: '刷新',
          onRefresh: onRefresh ?? () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: const [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('内容')),
              ),
            ],
          ),
        ),
      ),
    );

Future<void> pullDown(WidgetTester tester) async {
  await tester.drag(
    find.byType(CustomScrollView),
    const Offset(0, 320),
    touchSlopY: 0,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('下拉过阈值触发 onRefresh，并把带容器的指示器拉出来', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      host(
        enabled: true,
        onRefresh: () async {
          refreshed += 1;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        },
      ),
    );

    await pullDown(tester);
    expect(refreshed, 1);
    expect(find.byType(M3EContainedLoadingIndicator), findsOneWidget);

    // 刷新结束后指示器收起
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('enabled=false 时不响应下拉刷新', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      host(enabled: false, onRefresh: () async => refreshed += 1),
    );

    await pullDown(tester);
    expect(refreshed, 0);
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('拉出指示器后 enabled 变 false：松手不再触发刷新', (tester) async {
    final enabled = ValueNotifier<bool>(true);
    addTearDown(enabled.dispose);
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (context, value, _) => M3ePullToRefresh(
              gesture: PullToRefreshGesture(),
              enabled: value,
              onRefresh: () async => refreshed += 1,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: const [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('内容')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 260));
    await tester.pump();

    enabled.value = false;
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(refreshed, 0);
  });

  testWidgets('onRefresh 抛异常时指示器也会收起', (tester) async {
    await tester.pumpWidget(
      host(enabled: true, onRefresh: () async => throw StateError('boom')),
    );

    await pullDown(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
  });

  testWidgets('触发距离已调轻：110dp 够用、60dp 不会误触', (tester) async {
    // 手感回归：m3e 默认 80 / 0.55 要手指走约 180dp 才触发（偏费力），
    // 现在 60 / 0.75 约 100dp。这里钉住两端，避免以后被无意调回去。
    var refreshed = 0;
    await tester.pumpWidget(
      host(enabled: true, onRefresh: () async => refreshed += 1),
    );
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, 60),
      touchSlopY: 0,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(refreshed, 0, reason: '轻拉不该触发');

    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, 110),
      touchSlopY: 0,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(refreshed, 1, reason: '110dp 应该够触发');
  });

  testWidgets('下拉时列表自身不再回弹：位移只来自刷新组件', (tester) async {
    /// 同一段下拉，分别用全局 Bouncing 物理与本页专用物理，
    /// 看滚动位置有没有被「自己」拉走（拉走就会出现第二层留白）。
    /// [physics] 里带的 gesture 必须和弹窗组件用的是同一个实例。
    Future<double> pixelsAfterPull({
      required ScrollPhysics physics,
      PullToRefreshGesture? pullGesture,
    }) async {
      final controller = ScrollController();
      // 先清空再挂载：在同一个元素树上直接换 physics 不会生效，
      // 两次对照必须各自是新树。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: M3ePullToRefresh(
              gesture: pullGesture ?? PullToRefreshGesture(),
              onRefresh: () async {},
              child: CustomScrollView(
                controller: controller,
                physics: physics,
                slivers: const [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('内容')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CustomScrollView)),
      );
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      final pixels = controller.position.pixels;
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      controller.dispose();
      return pixels;
    }

    // 对照：全局 Bouncing 时列表自己也会被拉下去（这就是那层多余留白）
    expect(
      await pixelsAfterPull(physics: AppScrollBehavior.physics),
      lessThan(0),
    );
    // 本页专用物理：顶部下拉整段被夹住，位移只由刷新组件表现
    final pullGesture = PullToRefreshGesture();
    expect(
      await pixelsAfterPull(
        pullGesture: pullGesture,
        physics: PullToRefreshScrollPhysics(
          gesture: pullGesture,
          parent: AppScrollBehavior.physics,
        ),
      ),
      0,
    );
  });

  testWidgets('回拉时先收小球，收完列表才开始滚', (tester) async {
    final scroll = ScrollController();
    final pullGesture = PullToRefreshGesture();
    addTearDown(scroll.dispose);
    final physics = PullToRefreshScrollPhysics(
      parent: AppScrollBehavior.physics,
      gesture: pullGesture,
    );
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: M3ePullToRefresh(
            gesture: pullGesture,
            onRefresh: () async {},
            child: CustomScrollView(
              controller: scroll,
              physics: physics,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
                SliverList.builder(
                  itemCount: 30,
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

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    // 先往下拉出小球（不松手）
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(find.byType(M3EContainedLoadingIndicator), findsOneWidget);
    expect(scroll.position.pixels, 0);

    // 往回上拉一段：小球收回去，列表仍不动
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(scroll.position.pixels, 0, reason: '小球没收回前列表不该滚');

    // 继续上拉（按真实手指粒度分步：一次挪几像素）：
    // 小球收完后，后面的位移才开始滚列表
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);
    expect(scroll.position.pixels, greaterThan(0), reason: '小球收完后列表开始滚');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('用力甩回顶部后不会卡住、也不留空白层', (tester) async {
    final scroll = ScrollController();
    final pullGesture = PullToRefreshGesture();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: M3ePullToRefresh(
            gesture: pullGesture,
            onRefresh: () async {},
            child: CustomScrollView(
              controller: scroll,
              physics: PullToRefreshScrollPhysics(
                parent: AppScrollBehavior.physics,
                gesture: pullGesture,
              ),
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

    // 先滚到列表中间
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

    // 用力甩回顶部（回弹到顶）
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 900),
      4000,
    );
    // 等回弹彻底停稳（Bouncing 的过冲回弹需要一段时间）
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, 0);
    // 顶部不该残留小球 / 空白层
    expect(find.byType(M3EContainedLoadingIndicator), findsNothing);

    // 关键：还能正常往上滚（修复前这里会卡住不动）
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -200),
      touchSlopY: 0,
    );
    await tester.pump();
    expect(scroll.position.pixels, greaterThan(0), reason: '甩回顶部后应能继续滚动');
  });
}
