import 'api/models.dart';
import 'file_name_collation.dart';

/// 同一目录内名称完全相同的一组文件。
///
/// [files] 保留服务端原始顺序。个人网盘接口按时间从新到旧返回，因此第一项
/// 是该组最新的文件；“保留最新”只需要选中其余项。
class DuplicateFileGroup {
  DuplicateFileGroup({required this.name, required List<LzFile> files})
    : files = List<LzFile>.unmodifiable(files),
      assert(files.length > 1);

  final String name;
  final List<LzFile> files;

  LzFile get newest => files.first;

  Set<String> get newestOnlySelection => {
    for (final file in files.skip(1)) file.id,
  };
}

/// 当前文件快照中的同名文件扫描结果。
class DuplicateFileScan {
  DuplicateFileScan(List<DuplicateFileGroup> groups)
    : groups = List<DuplicateFileGroup>.unmodifiable(groups),
      fileCount = groups.fold(0, (total, group) => total + group.files.length);

  /// 按文件名排序后的同名组。
  final List<DuplicateFileGroup> groups;

  /// 所有同名组包含的文件总数，不是可删除数量。
  final int fileCount;

  int get groupCount => groups.length;

  int get removableCount =>
      groups.fold(0, (total, group) => total + group.files.length - 1);

  bool get isEmpty => groups.isEmpty;
}

/// 从目录文件快照中找出名称相同且至少有两个不同文件 id 的组。
///
/// 分组名称保持接口返回的精确名称，不区分大小写或做 Unicode 归一化；文件
/// id 重复时只保留第一次出现，避免分页重叠把同一个文件算成两份。
DuplicateFileScan scanDuplicateFiles(Iterable<LzFile> files) {
  final seenIds = <String>{};
  final byName = <String, List<LzFile>>{};
  for (final file in files) {
    if (!seenIds.add(file.id)) continue;
    byName.putIfAbsent(file.name, () => <LzFile>[]).add(file);
  }

  final groups =
      <DuplicateFileGroup>[
        for (final entry in byName.entries)
          if (entry.value.length > 1)
            DuplicateFileGroup(name: entry.key, files: entry.value),
      ]..sort((a, b) {
        final byCollation = lanzouNameSortKey(a.name)
            .compareTo(lanzouNameSortKey(b.name));
        if (byCollation != 0) return byCollation;
        return a.name.compareTo(b.name);
      });

  return DuplicateFileScan(groups);
}
