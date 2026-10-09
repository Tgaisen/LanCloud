import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    // 放到可滚动容器里：卡片高度由内容决定（和属性弹窗里的情形一致）
    body: SingleChildScrollView(
      child: Center(child: SizedBox(width: 400, child: child)),
    ),
  ),
);

double descOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byType(SelectionArea),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

void main() {
  testWidgets('属性卡简介可选择，并且出现时是淡入而不是瞬间显示', (tester) async {
    await tester.pumpWidget(
      host(
        const PropertyHeaderCard(
          icon: Icons.folder_outlined,
          title: '测试文件夹',
          desc: '这是简介，应该可以被选中复制',
        ),
      ),
    );

    // 简介用 SelectionArea + Text：能选中复制，又不会自带上下滚动
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    // 第一帧还在动画起点，不是瞬间出现
    expect(descOpacity(tester), lessThan(0.5));

    await tester.pumpAndSettle();
    expect(descOpacity(tester), 1.0);
  });

  // 弹窗打开后简介才拉取回来：卡片高度要跟着平滑变高，不能瞬间跳
  testWidgets('简介更新后卡片高度是平滑变化的', (tester) async {
    Future<double> pumpWithDesc(String desc) async {
      await tester.pumpWidget(
        host(
          PropertyHeaderCard(
            icon: Icons.folder_outlined,
            title: '测试文件',
            desc: desc,
          ),
        ),
      );
      return tester.getSize(find.byType(PropertyHeaderCard)).height;
    }

    await pumpWithDesc('短简介');
    await tester.pumpAndSettle();
    final short = tester.getSize(find.byType(PropertyHeaderCard)).height;

    await pumpWithDesc(List.filled(20, '这是一段更长的简介').join('，'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final middle = tester.getSize(find.byType(PropertyHeaderCard)).height;
    await tester.pumpAndSettle();
    final tall = tester.getSize(find.byType(PropertyHeaderCard)).height;

    expect(tall, greaterThan(short));
    expect(middle, greaterThan(short));
    expect(middle, lessThan(tall));
  });

  testWidgets('系统要求少动效时简介直接显示', (tester) async {
    SystemMotion.reduceMotion.value = true;
    addTearDown(() => SystemMotion.reduceMotion.value = false);

    await tester.pumpWidget(
      host(
        const PropertyHeaderCard(
          icon: Icons.folder_outlined,
          title: '测试文件夹',
          desc: '简介',
        ),
      ),
    );
    expect(descOpacity(tester), 1.0);
  });
}
