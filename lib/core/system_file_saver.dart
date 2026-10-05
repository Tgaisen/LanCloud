import 'package:flutter/services.dart';

/// 系统「保存文件」对话框：Android 上是 Intent.ACTION_CREATE_DOCUMENT。
/// 应用把生成在私有目录里的文件写到用户选择的位置，
/// 通过 SAF 写入不需要任何存储权限，也不需要 MANAGE_EXTERNAL_STORAGE。
class SystemFileSaver {
  SystemFileSaver._();

  static const _channel = MethodChannel('lancloud/file_picker');

  /// 把 [sourcePath] 的文件保存到用户选择的位置。
  ///
  /// [fileName] 是保存对话框里预填的文件名，[mime] 决定系统筛选的类型。
  /// 返回系统实际使用的文件名（用户可能改名，重名时系统会追加序号）；
  /// 用户取消时返回 null，写入失败时抛 PlatformException。
  static Future<String?> save({
    required String sourcePath,
    required String fileName,
    required String mime,
  }) async {
    final name = await _channel.invokeMethod<String>('saveFile', {
      'path': sourcePath,
      'fileName': fileName,
      'mime': mime,
    });
    if (name == null || name.isEmpty) return null;
    return name;
  }
}
