import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';

Widget host(Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
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
    // 没有副标题时，标题与 42dp 图标块垂直居中。
    expect(
      tester.getCenter(find.text('测试文件夹')).dy,
      moreOrLessEquals(
        tester.getCenter(find.byIcon(Icons.folder_outlined)).dy,
        epsilon: 0.5,
      ),
    );
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

    // 简介默认只占 4 行；长内容可以展开，展开后卡片继续顺滑增高。
    expect(find.text('展开'), findsOneWidget);
    final descriptionCard = tester.getRect(
      find.byKey(const ValueKey('property-description-card')),
    );
    final toggle = tester.getRect(
      find.byKey(const ValueKey('property-description-toggle')),
    );
    expect(toggle.left - descriptionCard.left, 16);
    expect(descriptionCard.bottom - toggle.bottom, 16);
    await tester.tap(find.text('展开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('收起'), findsOneWidget);
    expect(
      tester.getSize(find.byType(PropertyHeaderCard)).height,
      greaterThan(tall),
    );
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

  testWidgets('属性详情值更新时淡入并轻微上移', (tester) async {
    await tester.pumpWidget(
      host(const PropertyDetailRow(label: '大小', value: '—')),
    );
    await tester.pumpAndSettle();
    final widthBefore = tester.getSize(find.byType(AnimatedSize)).width;

    await tester.pumpWidget(
      host(const PropertyDetailRow(label: '大小', value: '2.0 MB')),
    );
    await tester.pump();

    expect(find.text('—'), findsOneWidget);
    expect(find.text('2.0 MB'), findsOneWidget);
    final incoming = find.text('2.0 MB');
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: incoming, matching: find.byType(FadeTransition)).first,
    );
    final slide = tester.widget<SlideTransition>(
      find.ancestor(of: incoming, matching: find.byType(SlideTransition)).first,
    );
    expect(fade.opacity.value, lessThan(1));
    expect(slide.position.value.dy, greaterThan(0));
    expect(
      tester.getSize(find.byType(AnimatedSize)).width,
      moreOrLessEquals(widthBefore, epsilon: 0.5),
    );
    expect(
      tester.getSize(incoming).width,
      moreOrLessEquals(widthBefore, epsilon: 0.5),
    );

    await tester.pumpAndSettle();
    expect(find.text('—'), findsNothing);
    expect(find.text('2.0 MB'), findsOneWidget);
  });
}
