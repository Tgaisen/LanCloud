import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/ui/common.dart';
import 'package:provider/provider.dart';

/// 复刻页面结构：顶栏浮层 + 等高占位 + 列表（顶栏不参与布局）。
class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => ProbePageState();
}

class ProbePageState extends State<ProbePage> {
  final ScrollController scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const headerHeight = kToolbarHeight;
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: scroll,
            slivers: [
              const SliverToBoxAdapter(
                child: SizedBox(height: headerHeight),
              ),
              SliverList.builder(
                itemCount: 40,
                itemBuilder: (context, index) =>
                    SizedBox(height: 60, child: Text('row $index')),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBarOverlay(
              height: headerHeight,
              child: AppBar(title: const Text('BAR')),
            ),
          ),
        ],
      ),
    );
  }
}

double topOf(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text, skipOffstage: false)).dy;

/// 顶栏本身的顶边位置（含浮层的位移）。
double barTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(AppBar, skipOffstage: false)).dy;

void main() {
  testWidgets('顶栏复用底栏进度：显示/隐藏都不改变列表的滚动位置', (tester) async {
    final app = AppController()..settings.hideTopBar = true;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: const MaterialApp(home: ProbePage()),
      ),
    );
    final state = tester.state<ProbePageState>(find.byType(ProbePage));
    state.scroll.jumpTo(400);
    await tester.pumpAndSettle();
    final rowBefore = topOf(tester, 'row 6');
    expect(barTop(tester), greaterThan(-0.5));

    // 滚动收起（ScrollTint 会把进度写进 barsHide）
    app.setBarsHideFromScroll(1);
    await tester.pumpAndSettle();
    expect(barTop(tester), lessThan(0));
    expect(topOf(tester, 'row 6'), rowBefore);
    expect(state.scroll.position.pixels, 400);

    // 切换视图：带动画调出（下滑显示），滚动位置与内容位置不变
    app.animateBarsHide(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = barTop(tester);
    expect(mid, lessThan(0));
    expect(mid, greaterThan(-kToolbarHeight));

    await tester.pump(const Duration(milliseconds: 300));
    expect(barTop(tester), greaterThan(-0.5));
    expect(topOf(tester, 'row 6'), rowBefore);
    expect(state.scroll.position.pixels, 400);
    app.dispose();
  });

  testWidgets('关闭“顶栏收起”时顶栏不跟随进度', (tester) async {
    final app = AppController()..settings.hideTopBar = false;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: const MaterialApp(home: ProbePage()),
      ),
    );
    final state = tester.state<ProbePageState>(find.byType(ProbePage));
    state.scroll.jumpTo(400);
    await tester.pumpAndSettle();

    app.setBarsHideFromScroll(1);
    await tester.pumpAndSettle();
    expect(barTop(tester), greaterThan(-0.5));
    app.dispose();
  });
}
