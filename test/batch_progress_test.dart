import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';

void main() {
  testWidgets('批量进度弹窗：标准标题、右侧计数与可取消进度，完成后自动关闭', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final gate = Completer<void>();
    late BatchProgressReport reportRef;
    final future = runBatchWithProgress(
      pageContext,
      title: '批量下载',
      total: 20,
      cancelable: true,
      run: (report, _) async {
        reportRef = report;
        report(1, 'a.zip');
        await gate.future;
        report(5, 'e.zip');
      },
    );

    await tester.pump();
    // 使用 AlertDialog 默认标题，不再单独居中覆盖。
    expect(tester.widget<Text>(find.text('批量下载')).textAlign, isNull);
    // 进度条 + 取消 + 计数 + 当前项
    expect(find.byType(M3eLinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-progress-cancel')), findsOneWidget);
    expect(find.text('1/20'), findsOneWidget);
    expect(find.text('a.zip'), findsOneWidget);

    // 当前项在左、计数在右；计数保留完整宽度，名称只占剩余空间。
    final detail = tester.getRect(find.text('a.zip'));
    final count = tester.getRect(find.text('1/20'));
    expect(detail.left, lessThan(count.left));
    final detailText = tester.widget<Text>(find.text('a.zip'));
    final countText = tester.widget<Text>(find.text('1/20'));
    expect(detailText.overflow, TextOverflow.ellipsis);
    expect(countText.softWrap, isFalse);
    expect(countText.style, same(detailText.style));
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(
      dialog.contentPadding!.resolve(TextDirection.ltr).right,
      12,
      reason: '取消按钮右边距应与解析弹窗的 12dp 一致',
    );
    // 进度条是确定值（不是无限循环）
    final indicator = tester.widget<M3eLinearProgressIndicator>(
      find.byType(M3eLinearProgressIndicator),
    );
    expect(indicator.value, isNotNull);

    // 汇报进度后计数与当前项更新
    reportRef(5, 'e.zip');
    await tester.pump();
    expect(find.text('5/20'), findsOneWidget);
    expect(find.text('e.zip'), findsOneWidget);

    // 完成后自动关闭
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await future;
  });

  testWidgets('批量进度弹窗：取消按钮只触发一次并返回取消结果', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    var cancelCount = 0;
    final future = runBatchWithProgress(
      pageContext,
      title: '批量删除',
      total: 3,
      cancelable: true,
      run: (report, cancelToken) async {
        report(1, 'a.zip');
        cancelToken.whenCancel.then((_) => cancelCount += 1);
        await cancelToken.whenCancel;
      },
    );

    await tester.pump();
    final cancel = find.byKey(const ValueKey('batch-progress-cancel'));
    await tester.tap(cancel);
    await tester.pump();
    await tester.pumpAndSettle();
    expect((await future).canceled, isTrue);
    expect(cancelCount, 1);
  });
}
