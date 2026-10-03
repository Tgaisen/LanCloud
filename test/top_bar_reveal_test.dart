import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/scroll_tint.dart';
import 'package:provider/provider.dart';

/// 复刻页面结构：顶栏浮层 + 等高占位 + 列表，
/// 并用 ScrollTint 按顶栏自身高度驱动收起进度。
class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => ProbePageState();
}

class ProbePageState extends State<ProbePage> {
  static const double headerHeight = kToolbarHeight;

  final ScrollController scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Scaffold(
      body: Stack(
        children: [
          ScrollTint(
            hideDistance: headerHeight,
            readBarsHidden: () => app.topBarHide.value,
            onBarsHidden:
                app.settings.hideTopBar ? app.setTopBarHideFromScroll : null,
            child: CustomScrollView(
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
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TopBarOverlay(
              height: headerHeight,
              background: Colors.white,
              builder: (context) => AppBar(
                title: const Text('BAR'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double topOf(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text, skipOffstage: false)).dy;

/// 顶栏本身的顶边位置（含浮层位移）。
double barTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(AppBar, skipOffstage: false)).dy;

void main() {
  testWidgets('顶栏与手指 1:1 跟随：滑动多少就上移多少，且不影响列表位置', (tester) async {
    final app = AppController()..settings.hideTopBar = true;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: const MaterialApp(home: ProbePage()),
      ),
    );
    final state = tester.state<ProbePageState>(find.byType(ProbePage));
    await tester.pumpAndSettle();
    final rowBefore = topOf(tester, 'row 0');

    // 滑过半个顶栏高度：顶栏只上移一半
    state.scroll.jumpTo(ProbePageState.headerHeight / 2);
    await tester.pumpAndSettle();
    expect(barTop(tester), -ProbePageState.headerHeight / 2);

    // 滑过一个顶栏高度：完全收起
    state.scroll.jumpTo(ProbePageState.headerHeight);
    await tester.pumpAndSettle();
    expect(barTop(tester), -ProbePageState.headerHeight);
    // 列表内容位置只由滚动决定，没有额外位移
    expect(topOf(tester, 'row 0') - rowBefore, -ProbePageState.headerHeight);

    // 切换视图：带动画下滑出现，滚动位置不变
    app.animateBarsHide(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = barTop(tester);
    expect(mid, lessThan(0));
    expect(mid, greaterThan(-ProbePageState.headerHeight));

    await tester.pump(const Duration(milliseconds: 300));
    expect(barTop(tester), greaterThan(-0.5));
    expect(state.scroll.position.pixels, ProbePageState.headerHeight);
    app.dispose();
  });

  testWidgets('回到顶部恢复显示；关闭“顶栏收起”时顶栏不跟随进度', (tester) async {
    final app = AppController()..settings.hideTopBar = true;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: const MaterialApp(home: ProbePage()),
      ),
    );
    final state = tester.state<ProbePageState>(find.byType(ProbePage));

    state.scroll.jumpTo(ProbePageState.headerHeight);
    await tester.pumpAndSettle();
    expect(barTop(tester), -ProbePageState.headerHeight);

    state.scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(barTop(tester), greaterThan(-0.5));

    // 关掉设置后，滚动不再驱动顶栏
    app.settings.hideTopBar = false;
    await tester.pumpAndSettle();
    state.scroll.jumpTo(ProbePageState.headerHeight);
    await tester.pumpAndSettle();
    expect(barTop(tester), greaterThan(-0.5));
    app.dispose();
  });
}
