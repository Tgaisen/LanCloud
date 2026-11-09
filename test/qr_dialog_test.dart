import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/qr_painter.dart';
import 'package:lancloud/ui/qr_scan.dart';
import 'package:material_ui/material_ui.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  testWidgets('二维码弹窗保持精简，Windows 识别时直接进入系统选图', (tester) async {
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
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is QrCodePainter,
      ),
      findsOneWidget,
    );
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

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      QrImageSource? source;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  source = await resolveQrImageSource(context);
                },
                child: const Text('scan'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      expect(source, QrImageSource.gallery);
      expect(find.byType(SheetListGroup), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
