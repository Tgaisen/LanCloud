import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/licenses_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  setUp(() {
    // 注册一条假许可证，免得依赖真实依赖树
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(
        <String>['fake_package'],
        '''
Fake package license

Copyright (c) 2026 LanCloud
''',
      );
    });
  });

  testWidgets('许可页用应用自己的顶栏，没有 Flutter 默认页头，且能打开包详情', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const LicensesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 顶栏：应用自己的返回按钮 + 页面标题
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    // 不再显示 «应用名 / 版本号 / powered by Flutter» 那块页头
    expect(find.textContaining('powered by Flutter'), findsNothing);
    expect(find.text('蓝云'), findsNothing);
    // 依赖包列表（按包名）
    expect(find.text('fake_package'), findsOneWidget);
    // 与「关于」页同款 MD3E 连接式列表组
    expect(find.byType(SegmentedSliverList), findsOneWidget);

    // 打开包详情：同样是应用自己的顶栏，正文可选中复制
    await tester.tap(find.text('fake_package'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byType(SelectionArea), findsWidgets);
    expect(find.textContaining('Copyright (c) 2026 LanCloud'), findsOneWidget);
  });
}
