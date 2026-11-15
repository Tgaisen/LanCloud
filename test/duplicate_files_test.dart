import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/duplicate_files.dart';

LzFile _file(String id, String name) =>
    LzFile(id: id, name: name, time: '2026-11-15', size: '1 M');

void main() {
  group('scanDuplicateFiles', () {
    test('只返回至少有两个不同文件 id 的同名组', () {
      final scan = scanDuplicateFiles([
        _file('1', 'a.zip'),
        _file('2', 'single.zip'),
        _file('3', 'a.zip'),
      ]);

      expect(scan.groups, hasLength(1));
      expect(scan.groups.single.name, 'a.zip');
      expect(scan.groups.single.files.map((file) => file.id), ['1', '3']);
      expect(scan.groupCount, 1);
      expect(scan.fileCount, 2);
      expect(scan.removableCount, 1);
    });

    test('分页重叠的相同 id 只计一次，也不会被误判为同名组', () {
      final scan = scanDuplicateFiles([
        _file('1', 'a.zip'),
        _file('1', 'a.zip'),
      ]);

      expect(scan.isEmpty, isTrue);
    });

    test('组内保留服务端新到旧顺序，保留最新会选中除首项外的文件', () {
      final scan = scanDuplicateFiles([
        _file('new', 'a.zip'),
        _file('old', 'a.zip'),
        _file('older', 'a.zip'),
      ]);

      final group = scan.groups.single;
      expect(group.newest.id, 'new');
      expect(group.files.map((file) => file.id), ['new', 'old', 'older']);
      expect(group.newestOnlySelection, {'old', 'older'});
    });

    test('组名按拼音排序，同名组内顺序不变', () {
      final scan = scanDuplicateFiles([
        _file('b1', '北京.zip'),
        _file('a1', '阿里.zip'),
        _file('b2', '北京.zip'),
        _file('a2', '阿里.zip'),
        _file('z1', 'Zeta.zip'),
        _file('z2', 'Zeta.zip'),
      ]);

      expect(scan.groups.map((group) => group.name), [
        '阿里.zip',
        '北京.zip',
        'Zeta.zip',
      ]);
      expect(scan.groups[1].files.map((file) => file.id), ['b1', 'b2']);
    });

    test('没有同名项时返回空结果', () {
      final scan = scanDuplicateFiles([
        _file('1', 'a.zip'),
        _file('2', 'b.zip'),
      ]);

      expect(scan.isEmpty, isTrue);
      expect(scan.groups, isEmpty);
      expect(scan.fileCount, 0);
      expect(scan.removableCount, 0);
    });
  });
}
