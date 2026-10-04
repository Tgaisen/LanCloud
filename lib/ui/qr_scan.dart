import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Icons;
import 'package:flutter/services.dart' show PlatformException;
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../core/file_picker_channel.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';

/// 二维码图片从哪里来。
enum QrImageSource {
  /// 调系统相机拍一张（ACTION_IMAGE_CAPTURE，无需相机权限）。
  camera,

  /// 从系统图库选一张（ACTION_PICK）。
  gallery,
}

/// 从图片字节里解码二维码（纯 Dart，不依赖相机与任何权限）。
///
/// 顶层函数，既能直接调用，也能交给 [compute] 放到后台 isolate，
/// 避免大图解码卡住 UI。图片里没有二维码 / 解码失败时返回 null。
String? decodeQrFromImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final image = _limitDecodeSize(decoded);
  // RGBLuminanceSource 需要 0xAARRGGBB 的像素数组。
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);
  final pixels = Int32List(image.width * image.height);
  for (var i = 0; i < pixels.length; i++) {
    final o = i * 4;
    pixels[i] =
        0xFF000000 | (rgba[o] << 16) | (rgba[o + 1] << 8) | rgba[o + 2];
  }
  try {
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    final text = QRCodeReader().decode(bitmap).text.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    // NotFoundException / FormatException / ChecksumException… 都当作「没识别到」
    return null;
  }
}

/// 相册原图往往 4000px 以上，缩到 2000px 内解码快很多，对识别率影响很小。
img.Image _limitDecodeSize(img.Image image, {int maxSide = 2000}) {
  final longest = image.width > image.height ? image.width : image.height;
  if (longest <= maxSide) return image;
  final scale = maxSide / longest;
  return img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

/// 「识别二维码」来源选择弹窗：拍照获取 / 从相册选取。
/// 样式与「选择登录方式」弹窗保持一致。
Future<QrImageSource?> showQrSourceSheet(BuildContext context) {
  final l10n = context.l10n;
  return showAppSheet<QrImageSource>(
    context,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.scan,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SegmentedList(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(l10n.scanTakePhoto),
                subtitle: Text(l10n.scanTakePhotoSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(QrImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(l10n.scanFromGallery),
                subtitle: Text(l10n.scanFromGallerySubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(QrImageSource.gallery),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 拍照 / 选图并解码二维码内容。
///
/// 返回二维码文本；用户取消、图片里没有二维码或出错时返回 null
/// （后两种情况会用 SnackBar 提示）。
Future<String?> scanQrFromImage(
  BuildContext context,
  QrImageSource source,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final String? path;
  try {
    path = source == QrImageSource.camera
        ? await ProviderFilePicker.takePhoto()
        : await _pickFromGallery();
  } on PlatformException catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e.code == 'no_camera' ? l10n.scanNoCameraApp : l10n.scanImageFailed,
        ),
      ),
    );
    return null;
  } catch (e, stack) {
    debugPrint('scan: 打开图片来源失败: $e\n$stack');
    messenger.showSnackBar(SnackBar(content: Text(l10n.scanImageFailed)));
    return null;
  }
  if (path == null) return null; // 用户取消

  try {
    final bytes = await File(path).readAsBytes();
    if (!context.mounted) return null;
    showLoadingDialog(context, l10n.scanDecoding);
    String? raw;
    try {
      raw = await compute(decodeQrFromImageBytes, bytes);
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
    if (raw == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.scanNoQrFound)));
    }
    return raw;
  } catch (e, stack) {
    debugPrint('scan: 图片识别失败: $e\n$stack');
    messenger.showSnackBar(SnackBar(content: Text(l10n.scanImageFailed)));
    return null;
  }
}

/// 从系统图库选一张图片（ACTION_PICK，不需要存储权限）。
Future<String?> _pickFromGallery() async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.image);
  if (picked == null || picked.files.isEmpty) return null;
  return picked.files.first.path;
}
