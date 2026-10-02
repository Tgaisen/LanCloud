import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/transfers_page.dart';
import 'package:provider/provider.dart';

TransferTask task(
  String id,
  String name, {
  required TransferStatus status,
}) {
  return TransferTask(
    id: id,
    kind: TransferKind.upload,
    name: name,
    accountUid: '',
    localFilePath: '/tmp/$name',
  )..status = status;
}

Future<(AppController, TransferManager)> host(WidgetTester tester) async {
  final app = AppController();
  final manager = TransferManager(app);
  manager.tasks.addAll([
    task('t1', 'a.zip', status: TransferStatus.failed),
    task('t2', 'b.zip', status: TransferStatus.failed),
    task('t3', 'c.zip', status: TransferStatus.done),
  ]);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<TransferManager>.value(value: manager),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const TransfersPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (app, manager);
}

bool retryEnabled(WidgetTester tester) {
  final action = tester.widget<BatchAction>(
    find.ancestor(
      of: find.text('重试'),
      matching: find.byType(BatchAction),
    ),
  );
  return action.onPressed != null;
}

void main() {
  testWidgets('长按进入多选：显示已选数量，重试仅对失败项可用', (tester) async {
    final (app, manager) = await host(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfers-selection-appbar')), findsOneWidget);
    expect(find.text('已选择 1 项'), findsOneWidget);
    // 选中的是失败项 → 重试可用
    expect(retryEnabled(tester), isTrue);

    // 再加选一个已完成项，计数更新
    await tester.tap(find.text('c.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(retryEnabled(tester), isTrue);

    // 只选已完成项时重试不可用
    await tester.tap(find.text('a.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(retryEnabled(tester), isFalse);

    // 退出多选
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(app.selectionMode, isFalse);
    expect(manager.tasks.length, 3);
    app.dispose();
  });

  testWidgets('多选删除：确认后移除选中记录', (tester) async {
    final (app, manager) = await host(tester);

    await tester.longPress(find.text('a.zip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('c.zip'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 确认弹窗
    expect(find.text('删除传输记录'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(manager.tasks.map((t) => t.id).toList(), ['t2']);
    expect(app.selectionMode, isFalse);
    app.dispose();
  });
}
