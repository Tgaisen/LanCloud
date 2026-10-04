import 'package:flutter/services.dart';

/// 通过原生 ACTION_GET_CONTENT 选择器选取文件（含云盘提供器），
/// 选中内容会被复制到应用缓存并返回本地路径。
class ProviderFilePicker {
  ProviderFilePicker._();

  static const _channel = MethodChannel('lancloud/file_picker');

  static Future<List<String>> pickFiles() async {
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
    final result = await _channel.invokeMethod<List<dynamic>>('takePhoto');
    if (result == null || result.isEmpty) return null;
    return '${result.first}';
  }
}
