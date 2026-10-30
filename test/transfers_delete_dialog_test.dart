import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('传输页删除弹窗：复选行在列表组里，组沿距内容边距 24dp', (tester) async {
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
      ProviderScope(
        overrides: [transferManagerProvider.overrideWithValue(manager)],
        child: ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const TransfersPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 长按进多选 → 底部多选条的「删除」（图标按钮，按 tooltip 定位）打开确认弹窗
    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
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

    // 与「恢复确认」弹窗一致：选项行放进列表组，行铺满组宽，组沿距内容 24dp
    final group = find.byType(DialogListGroup);
    expect(group, findsOneWidget);
    final row = find.descendant(of: group, matching: find.byType(M3ePickTile));
    expect(
      tester.getSize(row).width,
      moreOrLessEquals(tester.getSize(group).width, epsilon: 0.5),
    );
    expect(
      tester.getTopLeft(group).dx - tester.getTopLeft(surface).dx,
      moreOrLessEquals(24, epsilon: 0.5),
    );

    // 关掉弹窗并退出多选再收尾：页面 dispose 时还会去改控制器
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    app.dispose();
  });
}
