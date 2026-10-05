import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_info.dart';

/// 运行日志：把错误和 debugPrint 输出写到本机文件。
/// 只保存在应用私有目录，只有用户主动「导出运行日志」时才会交给其他应用。
///
/// 滚动策略：lancloud.log 写满一份就滚成 lancloud.1.log，旧的依次后移，
/// 最老的一份被删除，磁盘占用有硬上限；同一位置的异常在去重窗口内
/// 只记录第一条，避免异常刷屏时反复同步写盘。
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const _fileName = 'lancloud.log';
  static const _rotatedPrefix = 'lancloud.';
  static const _rotatedSuffix = '.log';

  /// 保留的旧日志份数：lancloud.1.log ~ lancloud.7.log。
  static const _rotatedCount = 7;

  /// 单个日志文件的默认上限，超过就滚动。
  static const _defaultMaxBytes = 512 * 1024;

  /// 同一位置重复报错的默认去重窗口。
  static const _defaultRepeatWindow = Duration(seconds: 60);

  File? _file;
  bool _ready = false;

  /// 当前文件已写入的字节数，用来判断何时滚动（不必每次都读文件长度）。
  int _size = 0;

  int _maxBytes = _defaultMaxBytes;
  Duration _repeatWindow = _defaultRepeatWindow;

  /// 去重窗口内的异常签名 → 上次写入时间与已省略次数。
  final Map<String, _RepeatEntry> _repeats = {};

  /// 应用启动时调用一次；失败不影响正常使用。
  ///
  /// [directory]、[maxBytes]、[repeatWindow] 仅供测试注入，
  /// 默认分别是应用文档目录下的 logs、512KB、60 秒。
  Future<void> init({
    Directory? directory,
    int? maxBytes,
    Duration? repeatWindow,
  }) async {
    _ready = false;
    try {
      final dir = directory ?? await _defaultDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, _fileName));
      _file = file;
      _size = 0;
      if (await file.exists()) _size = await file.length();
      _maxBytes = maxBytes ?? _defaultMaxBytes;
      _repeatWindow = repeatWindow ?? _defaultRepeatWindow;
      _repeats.clear();
      _ready = true;
      // 上次会话写超了上限：先滚动，再记录本次启动
      if (_size > _maxBytes) _rotate();
      log('app', '启动 LanCloud $appVersion ($appBuild) · $_environment');
    } catch (_) {
      // 拿不到目录时静默跳过
    }
  }

  Future<Directory> _defaultDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'logs'));
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
    final now = DateTime.now();
    var note = '';
    if (level == 'E') {
      final signature = _signature(tag, message);
      final repeat = _repeats[signature];
      if (repeat != null && now.difference(repeat.at) < _repeatWindow) {
        // 窗口内重复：只计数，不写盘
        repeat.suppressed += 1;
        return;
      }
      if (repeat != null && repeat.suppressed > 0) {
        note = '（相同错误重复 ${repeat.suppressed} 次已省略）';
      }
      _repeats[signature] = _RepeatEntry(now);
      if (_repeats.length > 200) {
        _repeats.removeWhere(
          (_, entry) => now.difference(entry.at) >= _repeatWindow,
        );
      }
    }
    final buffer = StringBuffer()
      ..writeln('${_timestamp(now)} [$level] $tag: $message$note');
    if (stack != null) buffer.writeln('$stack');
    final text = buffer.toString();
    try {
      file.writeAsStringSync(text, mode: FileMode.append);
    } catch (_) {
      // 写日志失败时忽略，避免影响主流程
      return;
    }
    _size += utf8.encode(text).length;
    if (_size > _maxBytes) _rotate();
  }

  /// 异常去重签名：位置 + 第一条消息，忽略每次都不同的堆栈。
  String _signature(String tag, Object? message) {
    var text = '$message';
    final newline = text.indexOf('\n');
    if (newline >= 0) text = text.substring(0, newline);
    text = text.trim();
    if (text.length > 160) text = text.substring(0, 160);
    return '$tag|$text';
  }

  /// 滚动一次：删掉最老的一份，其余依次后移，当前文件变成 1 号。
  void _rotate() {
    _size = 0;
    final file = _file;
    if (file == null) return;
    try {
      final dir = file.parent.path;
      final oldest = File(_partPath(dir, _rotatedCount));
      if (oldest.existsSync()) oldest.deleteSync();
      for (var index = _rotatedCount - 1; index >= 1; index--) {
        final from = File(_partPath(dir, index));
        if (from.existsSync()) from.renameSync(_partPath(dir, index + 1));
      }
      file.renameSync(_partPath(dir, 1));
    } catch (_) {
      // 滚动失败时继续往当前文件写，不影响主流程
    }
  }

  String _partPath(String dir, int index) =>
      p.join(dir, '$_rotatedPrefix$index$_rotatedSuffix');

  String _timestamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  String _two(int value) => value.toString().padLeft(2, '0');

  /// 导出文件名用的时间戳：20261005-193000。
  String _stamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}'
      '-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  /// 导出顺序：最老的旧日志 → 最新的当前日志（只包含存在的文件）。
  Future<List<File>> exportParts() async {
    final file = _file;
    if (file == null) return const [];
    final dir = file.parent.path;
    final parts = <File>[];
    for (var index = _rotatedCount; index >= 1; index--) {
      final part = File(_partPath(dir, index));
      if (await part.exists()) parts.add(part);
    }
    if (await file.exists()) parts.add(file);
    return parts;
  }

  /// 导出用文件：把保留的旧日志和当前日志合并成一个 txt，放到临时目录。
  /// 没有内容时返回 null。
  Future<File?> exportBundle() async {
    final parts = await exportParts();
    if (parts.isEmpty) return null;
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer.write(await part.readAsString());
    }
    final dir = await getTemporaryDirectory();
    final out = File(
      p.join(dir.path, 'lancloud-log-${_stamp(DateTime.now())}.txt'),
    );
    await out.writeAsString(buffer.toString(), flush: true);
    return out;
  }
}

/// 某个异常签名上次写入的时间，以及窗口内被省略的次数。
class _RepeatEntry {
  _RepeatEntry(this.at);

  final DateTime at;
  int suppressed = 0;
}
