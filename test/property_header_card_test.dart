import 'package:flutter/material.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

double descOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byType(SelectableText),
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

    // 简介用 SelectableText（长按 / 拖选可复制）
    expect(find.byType(SelectableText), findsOneWidget);
    // 第一帧还在动画起点，不是瞬间出现
    expect(descOpacity(tester), lessThan(0.5));

    await tester.pumpAndSettle();
    expect(descOpacity(tester), 1.0);
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
