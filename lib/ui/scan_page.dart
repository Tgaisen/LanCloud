import 'package:flutter/material.dart' hide Icons;
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';

/// 扫码页：识别二维码后把内容回传给调用方（弹窗关闭时返回 null）。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 取第一个有内容的二维码结果。
  String? _firstValue(BarcodeCapture? capture) {
    for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      return raw;
    }
    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = _firstValue(capture);
    if (raw == null) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  /// 从相册选一张图片识别二维码。
  Future<void> _pickFromGallery() async {
    if (_picking) return;
    setState(() => _picking = true);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      final path = picked?.files.firstOrNull?.path;
      if (path == null) return;
      final raw = _firstValue(await _controller.analyzeImage(path));
      if (!mounted) return;
      if (raw == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.scanNoQrFound)),
        );
        return;
      }
      _handled = true;
      Navigator.of(context).pop(raw);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.scanImageFailed)),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.scan),
        actions: [
          IconButton(
            tooltip: l10n.scanTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: l10n.scanFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _picking ? null : _pickFromGallery,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.scanCameraFailed,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
          // 取景框
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 3),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              l10n.scanHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
