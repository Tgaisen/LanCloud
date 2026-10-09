import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/app_localizations_zh.dart';
import 'package:lancloud/ui/qr_scan.dart';
import 'package:qr/qr.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 用纯 Dart 画一张「白底 + 黑块 + 静区」的二维码 PNG，作为相册图片夹具。
img.Image _qrImage(String data, {int scale = 8, int quiet = 4}) {
  final code = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qr = QrImage(code);
  final modules = qr.moduleCount;
  final side = (modules + quiet * 2) * scale;
  final image = img.Image(width: side, height: side);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  for (var y = 0; y < modules; y++) {
    for (var x = 0; x < modules; x++) {
      if (!qr.isDark(y, x)) continue;
      final left = (quiet + x) * scale;
      final top = (quiet + y) * scale;
      img.fillRect(
        image,
        x1: left,
        y1: top,
        x2: left + scale - 1,
        y2: top + scale - 1,
        color: black,
      );
    }
  }
  return image;
}

void main() {
  final zh = AppLocalizationsZh();

  test('相册二维码解码：能把图片里的内容识别出来', () {
    const data = 'https://wwa.lanzouq.com/abcdef';
    final png = img.encodePng(_qrImage(data));
    expect(decodeQrFromImageBytes(png), data);
  });

  test('图片里没有二维码时返回 null', () {
    final image = img.Image(width: 64, height: 64);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    expect(decodeQrFromImageBytes(img.encodePng(image)), isNull);
  });

  testWidgets('识别二维码弹窗：拍照获取 / 从相册选取两个入口', (WidgetTester tester) async {
    QrImageSource? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showQrSourceSheet(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(zh.scanTakePhoto), findsOneWidget);
    expect(find.text(zh.scanFromGallery), findsOneWidget);

    await tester.tap(find.text(zh.scanFromGallery));
    await tester.pumpAndSettle();
    expect(picked, QrImageSource.gallery);
  });
}
