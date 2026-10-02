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
}
