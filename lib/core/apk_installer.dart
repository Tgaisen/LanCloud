import 'package:flutter/services.dart';

/// 通过原生通道安装 APK（Android 8+ 会先引导开启“未知来源”权限）。
class ApkInstaller {
  ApkInstaller._();

  static const _channel = MethodChannel('lancloud/installer');

  static Future<void> installApk(String path) async {
    await _channel.invokeMethod<bool>('installApk', {'path': path});
  }
}
