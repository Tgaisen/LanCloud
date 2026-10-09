import 'package:flutter/material.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/ui/common.dart';

void main() {
  // 顶栏里的搜索框出现 / 消失要有过渡，别直接闪出来
  testWidgets('顶栏搜索框显示与隐藏都有过渡动画', (tester) async {
    var searching = false;
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: StatefulBuilder(
              builder: (context, setStateIn) {
                setState = setStateIn;
                return AppBarSearchSwitcher(
                  searching: searching,
                  title: const Text('网盘'),
                  searchField: const TextField(),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('网盘'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // 打开搜索：搜索框淡入（中间帧透明度在 0~1 之间）
    setState(() => searching = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(TextField), findsOneWidget);
    expect(
      _fadeValues(tester, find.byType(TextField)),
      anyElement(lessThan(1)),
    );

    await tester.pumpAndSettle();
    expect(_fadeValues(tester, find.byType(TextField)), everyElement(1.0));

    // 关闭搜索：标题回来时同样是渐显
    setState(() => searching = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('网盘'), findsOneWidget);
    expect(_fadeValues(tester, find.text('网盘')), anyElement(lessThan(1)));

    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(_fadeValues(tester, find.text('网盘')), everyElement(1.0));
  });
}

/// 某个子树外面包着的 FadeTransition 当前透明度（动画中的中间值）。
List<double> _fadeValues(WidgetTester tester, Finder target) => tester
    .widgetList<FadeTransition>(
      find.ancestor(
        of: target,
        matching: find.descendant(
          of: find.byType(AppBarSearchSwitcher),
          matching: find.byType(FadeTransition),
        ),
      ),
    )
    .map((fade) => fade.opacity.value)
    .toList();
