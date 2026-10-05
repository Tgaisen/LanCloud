import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_log.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lancloud-log-test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> initLog({
    int maxBytes = 512 * 1024,
    Duration repeatWindow = const Duration(seconds: 60),
  }) => AppLog.instance.init(
    directory: dir,
    maxBytes: maxBytes,
    repeatWindow: repeatWindow,
  );

  File currentFile() => File(p.join(dir.path, 'lancloud.log'));

  File rotatedFile(int index) => File(p.join(dir.path, 'lancloud.$index.log'));

  test('未超过上限时只保留当前文件', () async {
    await initLog();
    AppLog.instance.log('test', 'hello');

    expect(await currentFile().readAsString(), contains('hello'));
    expect(rotatedFile(1).existsSync(), isFalse);
  });

  test('写满后滚动，最多保留 7 份旧日志并删掉最老的', () async {
    await initLog(maxBytes: 200);
    for (var index = 0; index < 60; index++) {
      AppLog.instance.log('test', 'entry-$index-${'x' * 40}');
    }

    for (var index = 1; index <= 7; index++) {
      expect(rotatedFile(index).existsSync(), isTrue, reason: '$index 号应存在');
    }
    expect(rotatedFile(8).existsSync(), isFalse);
    // 目录里只有 7 份旧日志 + 当前日志
    final names = Directory(dir.path)
        .listSync()
        .map((entity) => p.basename(entity.path))
        .toSet();
    expect(names, hasLength(8));
  });

  test('导出按 最老 → 最新 拼接，被删掉的旧内容不再出现', () async {
    await initLog(maxBytes: 200);
    for (var index = 0; index < 60; index++) {
      AppLog.instance.log('test', 'entry-$index ${'y' * 40}');
    }

    final parts = await AppLog.instance.exportParts();
    expect(parts, hasLength(8));
    final text = StringBuffer();
    for (final part in parts) {
      text.write(await part.readAsString());
    }
    final numbers = RegExp(r'entry-(\d+) ')
        .allMatches(text.toString())
        .map((match) => int.parse(match.group(1)!))
        .toList();
    expect(numbers, isNotEmpty);
    expect(numbers.last, 59);
    expect(numbers.first, greaterThan(0));
    // 序号连续递增，说明导出顺序是 最老 → 最新
    expect(
      numbers,
      orderedEquals(List.generate(numbers.length, (i) => numbers.first + i)),
    );
  });

  test('同一位置的异常在去重窗口内只写一条', () async {
    await initLog();
    AppLog.instance.error('net', 'Bad state: boom', null);
    AppLog.instance.error('net', 'Bad state: boom', null);
    AppLog.instance.error('net', 'Bad state: boom', null);
    AppLog.instance.error('net', 'other failure', null);

    final text = await currentFile().readAsString();
    expect('Bad state: boom'.allMatches(text).length, 1);
    expect(text, contains('other failure'));
  });

  test('超过去重窗口后再次记录并标注省略次数', () async {
    await initLog(repeatWindow: const Duration(milliseconds: 80));
    AppLog.instance.error('net', 'boom', null);
    AppLog.instance.error('net', 'boom', null);
    AppLog.instance.error('net', 'boom', null);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    AppLog.instance.error('net', 'boom', null);

    final text = await currentFile().readAsString();
    expect(text, contains('（相同错误重复 2 次已省略）'));
  });
}
