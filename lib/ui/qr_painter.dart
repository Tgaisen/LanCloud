import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:qr/qr.dart';

/// 极简二维码绘制器：固定白底、黑色模块和 4 模块静区。
///
/// 不使用第三方 Flutter 二维码 Widget，避免布局约束、Material 版本拆分和
/// 渲染包维护状态影响弹窗；编码仍由活跃维护的纯 Dart `qr` 包完成。
class QrCodePainter extends CustomPainter {
  QrCodePainter(this.data)
    : _qrImage = QrImage(
        QrCode(
          payload: QrPayload.fromString(data),
          errorCorrectLevel: QrErrorCorrectLevel.medium,
        ),
      );

  /// QR 规范要求的最小静区，确保相机和扫码库能稳定定位。
  static const int quietZoneModules = 4;

  static const Color _background = Color(0xFFFFFFFF);
  static const Color _foreground = Color(0xFF000000);

  final String data;
  final QrImage _qrImage;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = _background);

    final moduleCount = _qrImage.moduleCount;
    final totalModules = moduleCount + quietZoneModules * 2;
    final side = math.min(size.width, size.height);
    final moduleSize = side / totalModules;
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    final paint = Paint()
      ..color = _foreground
      ..isAntiAlias = false;

    for (var y = 0; y < moduleCount; y++) {
      for (var x = 0; x < moduleCount; x++) {
        if (!_qrImage.isDark(y, x)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            left + (quietZoneModules + x) * moduleSize,
            top + (quietZoneModules + y) * moduleSize,
            moduleSize,
            moduleSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(QrCodePainter oldDelegate) => oldDelegate.data != data;
}
