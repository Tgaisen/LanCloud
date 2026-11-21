import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'platform_capabilities.dart';
import 'platform_support.dart';

/// Android 文档提供器选择端口。
abstract interface class DocumentProviderPicker {
  Future<List<String>> pickFiles();
}

/// `file_picker` 系统文件选择端口，返回值保留可空路径供上层统一过滤。
abstract interface class SystemFilePicker {
  Future<List<String?>> pickFiles({required String dialogTitle});
}

final class _AndroidDocumentProviderPicker implements DocumentProviderPicker {
  const _AndroidDocumentProviderPicker();

  @override
  Future<List<String>> pickFiles() async {
    final result =
        await ProviderFilePicker._channel.invokeMethod<List<dynamic>>(
          'pickFiles',
        ) ??
        const [];
    return [for (final path in result) '$path'];
  }
}

final class _DefaultSystemFilePicker implements SystemFilePicker {
  const _DefaultSystemFilePicker();

  @override
  Future<List<String?>> pickFiles({required String dialogTitle}) async {
    final picked = await FilePicker.pickFiles(dialogTitle: dialogTitle);
    return [for (final file in picked) file.path];
  }
}

/// 通过原生 ACTION_GET_CONTENT 选择器选取文件（含云盘提供器），
/// 选中内容会被复制到应用缓存并返回本地路径。
///
/// 没有文档提供器通道的平台改用 file_picker 的系统选择器；返回值本来就是
/// 本地路径，不需要再复制。
class ProviderFilePicker {
  ProviderFilePicker._();

  static const _channel = MethodChannel('lancloud/file_picker');

  static Future<List<String>> pickFiles({
    required String dialogTitle,
    PlatformCapabilities? capabilities,
    DocumentProviderPicker documentProviderPicker =
        const _AndroidDocumentProviderPicker(),
    SystemFilePicker systemFilePicker = const _DefaultSystemFilePicker(),
  }) async {
    final currentCapabilities = capabilities ?? PlatformCapabilities.current;
    if (currentCapabilities.supportsDocumentProviderUpload) {
      return documentProviderPicker.pickFiles();
    }
    final picked = await systemFilePicker.pickFiles(dialogTitle: dialogTitle);
    return [
      for (final path in picked)
        if (path != null && path.isNotEmpty) path,
    ];
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
