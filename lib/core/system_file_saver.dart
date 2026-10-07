import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'platform_support.dart';

/// 系统「保存文件」对话框：Android 上是 Intent.ACTION_CREATE_DOCUMENT。
/// 应用把生成在私有目录里的文件写到用户选择的位置，
/// 通过 SAF 写入不需要任何存储权限，也不需要 MANAGE_EXTERNAL_STORAGE。
///
/// 桌面端没有这条原生通道，改用 file_picker 的另存为对话框 + 应用自己复制。
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
    if (PlatformSupport.isDesktop) {
      return _saveOnDesktop(
        sourcePath: sourcePath,
        fileName: fileName,
        mime: mime,
      );
    }
    final name = await _channel.invokeMethod<String>('saveFile', {
      'path': sourcePath,
      'fileName': fileName,
      'mime': mime,
    });
    if (name == null || name.isEmpty) return null;
    return name;
  }

  /// 桌面端另存为：对话框只返回目标路径，文件由应用自己复制过去。
  /// 返回实际使用的文件名；用户取消时返回 null。
  static Future<String?> _saveOnDesktop({
    required String sourcePath,
    required String fileName,
    required String mime,
  }) async {
    final extensions = _extensionsFor(mime);
    var target = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
    );
    if (target == null || target.isEmpty) return null;
    // 对话框没带扩展名时补上源文件的扩展名
    if (p.extension(target).isEmpty) {
      final ext = p.extension(sourcePath);
      if (ext.isNotEmpty) target = '$target$ext';
    }
    await File(sourcePath).copy(target);
    return p.basename(target);
  }

  /// MIME → 另存为对话框的文件类型过滤。
  static List<String> _extensionsFor(String mime) => switch (mime) {
    'application/json' => const ['json'],
    'text/plain' => const ['txt', 'log'],
    _ => const <String>[],
  };
}
