import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/first_run_terms.dart';
import 'package:lancloud/ui/system_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('安全区在 Scaffold 清空 padding 后仍保留 viewPadding', (tester) async {
    late EdgeInsets insets;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.fromLTRB(6, 120, 9, 96),
          ),
          child: Builder(
            builder: (context) {
              insets = systemUiSafeInsets(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(insets, const EdgeInsets.fromLTRB(6, 120, 9, 96));
  });

  testWidgets('欢迎页滚动视口铺满全屏，安全区只放在滚动内容里', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.fromLTRB(0, 120, 0, 96),
          ),
          child: child!,
        ),
        home: FirstRunTerms(onAccepted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    // Bouncing 回弹的滚动视口不能被安全区缩小，否则只会在状态栏 /
    // 导航栏边缘被裁断；安全区应是视口内部的 padding。
    expect(
      tester.getSize(find.byType(SingleChildScrollView)),
      const Size(400, 800),
    );
    expect(tester.getTopLeft(find.byType(Image)).dy, greaterThanOrEqualTo(120));
  });

  testWidgets('欢迎页的导航栏也沉浸：透明、不加系统遮罩、图标随主题', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: FirstRunTerms(onAccepted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(FirstRunTerms),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    // 和主界面同一份系统栏样式：状态栏 / 导航栏都透明
    expect(region.value.statusBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarDividerColor, Colors.transparent);
    // Android 15+ 强制透明，垫在后面的系统遮罩必须关掉
    expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    // 浅色主题 → 导航栏用深色图标
    expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('协议勾选读出完整句子，两个协议链接保持独立可访问', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: FirstRunTerms(onAccepted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('我已阅读并同意用户协议与隐私政策'), findsOneWidget);
    expect(find.bySemanticsLabel('用户协议'), findsOneWidget);
    expect(find.bySemanticsLabel('隐私政策'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('大屏欢迎页：勾选协议后才启用下一步并保存同意版本', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: FirstRunTerms(onAccepted: () => accepted = true),
      ),
    );
    await tester.pumpAndSettle();

    final next = find.widgetWithText(FilledButton, '下一步');
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    // 大屏只约束操作宽度，不把按钮拉成整屏宽。
    expect(tester.getSize(next).width, lessThanOrEqualTo(360));

    final checkbox = find.byType(Checkbox);
    expect(find.byType(CheckboxListTile), findsNothing);
    final consentRow = find
        .ancestor(of: checkbox, matching: find.byType(Row))
        .first;
    expect(tester.getSize(consentRow).width, lessThanOrEqualTo(400));
    expect(
      tester.getCenter(consentRow).dx,
      closeTo(tester.getCenter(next).dx, 1),
    );
    // 普通文案区域不响应勾选，只有 Checkbox 本身可以切换。
    final copy = find.byKey(const ValueKey('agreement-copy'));
    await tester.tapAt(tester.getTopLeft(copy) + const Offset(8, 10));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);

    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('terms_accepted_version'), isNotNull);
  });
}
