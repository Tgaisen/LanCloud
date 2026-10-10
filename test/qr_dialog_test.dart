import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('二维码弹窗：只留二维码 + 关闭按钮，不再显示链接文本', (tester) async {
    const url = 'https://share.example/f1';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showQrDialog(context, title: 'a.zip', url: url, pwd: '1234'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 链接文本不显示（二维码本身就是链接）
    expect(find.text(url), findsNothing);
    expect(find.textContaining('share.example'), findsNothing);
    // 只剩一个「关闭」按钮
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('复制链接'), findsNothing);
    // 关闭按钮用原来的主操作样式（填充按钮）
    expect(
      find.ancestor(of: find.text('关闭'), matching: find.byType(FilledButton)),
      findsOneWidget,
    );
    // 提取码仍然提示（二维码里不含它）
    expect(find.textContaining('1234'), findsOneWidget);
  });
}
