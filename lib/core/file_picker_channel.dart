import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'platform_support.dart';

/// 通过原生 ACTION_GET_CONTENT 选择器选取文件（含云盘提供器），
/// 选中内容会被复制到应用缓存并返回本地路径。
///
/// 桌面端没有这条原生通道：换成 file_picker 的系统选择器，
/// 返回的本来就是本地路径，不需要再复制。
class ProviderFilePicker {
  ProviderFilePicker._();

  static const _channel = MethodChannel('lancloud/file_picker');

  static Future<List<String>> pickFiles() async {
    if (PlatformSupport.isDesktop) {
      final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
      return [
        for (final file in picked?.files ?? const <PlatformFile>[])
          if (file.path != null && file.path!.isNotEmpty) file.path!,
      ];
    }
    final result =
        await _channel.invokeMethod<List<dynamic>>('pickFiles') ?? const [];
    return [for (final path in result) '$path'];
  }

  /// 调系统相机拍一张照片（ACTION_IMAGE_CAPTURE），返回本地路径；
  /// 用户取消时返回 null；设备没有可用相机 App 时抛
  /// `PlatformException(code: 'no_camera')`。
  ///
  /// 应用不声明 CAMERA 权限，因此拍照全程无需任何授权，
  /// 照片由系统相机 App 写入本应用缓存目录（FileProvider）。
  static Future<String?> takePhoto() async {
    // 桌面端没有相机入口（界面也不会给出这个选项）
    if (PlatformSupport.isDesktop) {
      throw PlatformException(code: 'no_camera');
    }
    final result = await _channel.invokeMethod<List<dynamic>>('takePhoto');
    if (result == null || result.isEmpty) return null;
    return '${result.first}';
  }
}
