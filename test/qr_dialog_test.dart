import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/qr_painter.dart';
import 'package:lancloud/ui/qr_scan.dart';
import 'package:material_ui/material_ui.dart';

import 'package:lancloud/l10n/delegates.dart';

final _zh = AppLocalizationsZh();

void main() {
  testWidgets('二维码弹窗保持精简', (tester) async {
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
  });

  testWidgets('Android 相机能力下显示拍照和相册入口', (tester) async {
    QrImageSource? source;
    await _pumpActionButton(
      tester,
      onPressed: (context) async {
        source = await resolveQrImageSource(
          context,
          capabilities: PlatformCapabilities.android,
        );
      },
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    expect(find.text(_zh.scanTakePhoto), findsOneWidget);
    expect(find.text(_zh.scanFromGallery), findsOneWidget);

    await tester.tap(find.text(_zh.scanFromGallery));
    await tester.pumpAndSettle();
    expect(source, QrImageSource.gallery);
  });

  testWidgets('Windows 与 iOS 无相机能力时直接进入系统选图', (tester) async {
    for (final (:name, :capabilities) in [
      (name: 'Windows', capabilities: PlatformCapabilities.windows),
      (name: 'iOS', capabilities: PlatformCapabilities.ios),
    ]) {
      QrImageSource? source;
      await _pumpActionButton(
        tester,
        onPressed: (context) async {
          source = await resolveQrImageSource(
            context,
            capabilities: capabilities,
          );
        },
      );

      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      expect(source, QrImageSource.gallery, reason: name);
      expect(find.byType(SheetListGroup), findsNothing, reason: name);
    }
  });
}

Future<void> _pumpActionButton(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) onPressed,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('scan'),
          ),
        ),
      ),
    ),
  );
}
