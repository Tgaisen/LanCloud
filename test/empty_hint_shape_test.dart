import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('空状态图标：套 9 边饼干（Cookie9Sided）形状外框', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: EmptyHint(icon: Icons.folder_open, text: '这个文件夹是空的'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 外框形状取自 M3 形状库：9 边饼干
    final clip = tester
        .widgetList<ClipPath>(find.byType(ClipPath))
        .firstWhere((c) => c.clipper is M3EClipper);
    expect((clip.clipper! as M3EClipper).shape, Shapes.c9SidedCookie);

    // 图标在形状里面（尺寸 / 配色跟着形状外框走）
    final scheme = Theme.of(tester.element(find.byType(EmptyHint))).colorScheme;
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(M3eShapedIcon),
        matching: find.byIcon(Icons.folder_open),
      ),
    );
    expect(icon.size, 36);
    expect(icon.color, scheme.onSecondaryContainer);

    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(M3eShapedIcon),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(box.color, scheme.secondaryContainer);
    expect(tester.getSize(find.byType(M3eShapedIcon)), const Size(72, 72));
  });

  testWidgets('首页空状态卡片：形状外框可以单独收到 64dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: EmptyHint(
            icon: Icons.push_pin_outlined,
            text: '可在此固定常用网盘目录',
            frameSize: 64,
            iconSize: 32,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(M3eShapedIcon)), const Size(64, 64));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byType(M3eShapedIcon),
              matching: find.byIcon(Icons.push_pin_outlined),
            ),
          )
          .size,
      32,
    );
  });
}
