import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_info.dart';

/// 运行日志：把错误和 debugPrint 输出写到本机文件。
/// 只保存在应用私有目录，只有用户主动「导出运行日志」时才会交给其他应用。
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const _fileName = 'lancloud.log';
  static const _rotatedName = 'lancloud.1.log';

  /// 单个日志文件上限，超过就轮转（保留一份旧的）。
  static const _maxBytes = 512 * 1024;

  File? _file;
  bool _ready = false;

  /// 应用启动时调用一次；失败不影响正常使用。
  Future<void> init() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'logs'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, _fileName));
      if (await file.exists() && await file.length() > _maxBytes) {
        final rotated = File(p.join(dir.path, _rotatedName));
        if (await rotated.exists()) await rotated.delete();
        await file.rename(rotated.path);
      }
      _file = file;
      _ready = true;
      log('app', '启动 LanCloud $appVersion ($appBuild) · $_environment');
    } catch (_) {
      // 拿不到目录时静默跳过
    }
  }

  String get _environment {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  void log(String tag, Object? message) => _write('I', tag, message, null);

  void error(String tag, Object? error, StackTrace? stack) =>
      _write('E', tag, error, stack);

  void _write(String level, String tag, Object? message, StackTrace? stack) {
    final file = _file;
    if (!_ready || file == null) return;
    final buffer = StringBuffer()
      ..writeln('${_timestamp(DateTime.now())} [$level] $tag: $message');
    if (stack != null) buffer.writeln('$stack');
    try {
      file.writeAsStringSync(buffer.toString(), mode: FileMode.append);
    } catch (_) {
      // 写日志失败时忽略，避免影响主流程
    }
  }

  String _timestamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  String _two(int value) => value.toString().padLeft(2, '0');

  /// 导出用文件：把轮转的旧日志和当前日志合并成一个 txt，放到临时目录。
  /// 没有内容时返回 null。
  Future<File?> exportBundle() async {
    final file = _file;
    if (file == null) return null;
    final buffer = StringBuffer();
    final rotated = File(p.join(file.parent.path, _rotatedName));
    if (await rotated.exists()) buffer.write(await rotated.readAsString());
    if (await file.exists()) buffer.write(await file.readAsString());
    if (buffer.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final out = File(
      p.join(
        dir.path,
        'lancloud-log-${DateTime.now().millisecondsSinceEpoch}.txt',
      ),
    );
    await out.writeAsString(buffer.toString(), flush: true);
    return out;
  }
}
