import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_support.dart';

/// 应用缓存：统计与清理。
///
/// 只涉及临时目录里的「本应用产物」——拖拽 / 选择文件 / 拍照留下的副本、
/// 备份与日志的导出残留、内嵌网页（WebView）的网页缓存等。
/// 账号、设置、正式日志（文档目录 `logs/`）和已下载的文件都不动。
class AppCache {
  AppCache._();

  /// 本应用在临时目录里创建的条目（Android 侧由 [MainActivity] 建立）。
  static const Set<String> _ownEntries = {'picked', 'drop', 'photo'};

  /// 本应用在临时目录里写出的导出文件前缀（备份 / 日志导出）。
  static const String _ownFilePrefix = 'lancloud-';

  /// 测试注入用；默认为 path_provider 的临时目录。
  @visibleForTesting
  static Future<Directory?> Function()? directoryProvider;

  static Future<Directory?> _dir() async {
    try {
      return await (directoryProvider?.call() ?? getTemporaryDirectory());
    } catch (_) {
      // 拿不到目录（测试 / 不支持的平台）时视为没有缓存
      return null;
    }
  }

  /// 移动端的缓存目录是应用私有的，可以整体清理；
  /// 桌面端的临时目录是系统共享的（Windows 的 %TEMP%），只删本应用自己的条目。
  static bool get _wholeDirectory => PlatformSupport.isMobile;

  /// 条目是否属于本应用：按「相对缓存目录的第一段」判断，
  /// 这样自己目录里的文件（`picked/xxx`）也算自己的。
  static bool _isOwn(Directory root, FileSystemEntity entity) {
    final top = p.split(p.relative(entity.path, from: root.path)).first;
    return _ownEntries.contains(top) || top.startsWith(_ownFilePrefix);
  }

  /// 当前缓存占用（字节）。目录不可用时返回 null。
  static Future<int?> size() async {
    final dir = await _dir();
    if (dir == null || !dir.existsSync()) return null;
    var total = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (!_wholeDirectory && !_isOwn(dir, entity)) continue;
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } catch (_) {
          // 单个文件读不到（正被占用等）：跳过
        }
      }
    } catch (_) {
      // 目录遍历失败：按已统计到的部分返回
    }
    return total;
  }

  /// 清空缓存，返回释放的字节数（目录不可用时返回 null）。
  static Future<int?> clear() async {
    final dir = await _dir();
    if (dir == null || !dir.existsSync()) return null;
    final before = await size() ?? 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (!_wholeDirectory && !_isOwn(dir, entity)) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // 正被占用的文件删不掉：跳过，不阻塞其余清理
        }
      }
    } catch (_) {
      // 目录读不了时直接返回已释放的部分
    }
    return before;
  }
}
