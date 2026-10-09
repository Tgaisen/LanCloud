import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('传输页删除弹窗：复选行铺满弹窗宽度（波纹不会被截断）', (tester) async {
    final app = AppController();
    final manager = TransferManager(app);
    manager.tasks.add(
      TransferTask(
        id: 't1',
        kind: TransferKind.upload,
        name: 'a.zip',
        accountUid: '',
        localFilePath: '/tmp/a.zip',
      )..status = TransferStatus.failed,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: app),
          ChangeNotifierProvider<TransferManager>.value(value: manager),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const TransfersPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 长按进多选 → 顶栏「删除」打开确认弹窗
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除传输记录'), findsOneWidget);
    expect(find.text('同时删除文件'), findsOneWidget);

    // 弹窗真正的内容面板（AlertDialog 自身是铺满屏幕的布局盒子）
    final surface = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Material),
        )
        .first;

    // 与「恢复确认」弹窗一致：复选行左右铺满弹窗，波纹覆盖整个宽度
    expect(
      tester.getSize(find.byType(CheckboxListTile)).width,
      moreOrLessEquals(tester.getSize(surface).width, epsilon: 0.5),
    );
    expect(
      tester.getTopLeft(find.byType(CheckboxListTile)).dx,
      moreOrLessEquals(tester.getTopLeft(surface).dx, epsilon: 0.5),
    );

    // 关掉弹窗并退出多选再收尾：页面 dispose 时还会去改控制器
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    app.dispose();
  });
}
