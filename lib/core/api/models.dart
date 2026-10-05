class LzFile {
  LzFile({
    required this.id,
    required this.name,
    required this.time,
    required this.size,
    this.downs = 0,
    this.hasPwd = false,
    this.hasDes = false,
  });

  final String id;
  final String name;
  final String time;
  final String size;
  final int downs;
  final bool hasPwd;
  final bool hasDes;

  factory LzFile.fromJson(Map<String, dynamic> j) => LzFile(
        id: '${j['id']}',
        name: '${j['name_all'] ?? j['name'] ?? ''}'.replaceAll('&amp;', '&'),
        time: '${j['time'] ?? ''}',
        size: '${j['size'] ?? ''}'.replaceAll(',', ''),
        downs: int.tryParse('${j['downs'] ?? 0}') ?? 0,
        hasPwd: j['onof'] != null
            ? '${j['onof']}' == '1'
            : (j['hasPwd'] == true || '${j['hasPwd']}' == 'true'),
        hasDes: j['is_des'] != null
            ? '${j['is_des']}' == '1'
            : (j['hasDes'] == true || '${j['hasDes']}' == 'true'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'time': time,
        'size': size,
        'downs': downs,
        'hasPwd': hasPwd,
        'hasDes': hasDes,
      };
}

class LzFolder {
  LzFolder({
    required this.id,
    required this.name,
    required this.desc,
    this.hasPwd = false,
  });

  final String id;
  final String name;
  final String desc;
  final bool hasPwd;

  factory LzFolder.fromJson(Map<String, dynamic> j) => LzFolder(
        id: '${j['fol_id'] ?? j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        desc: '${j['folder_des'] ?? j['desc'] ?? ''}'
            .replaceAll('[', '')
            .replaceAll(']', '')
            .trim(),
        hasPwd: j['onof'] != null
            ? '${j['onof']}' == '1'
            : (j['hasPwd'] == true || '${j['hasPwd']}' == 'true'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': desc,
        'hasPwd': hasPwd,
      };
}

class PathNode {
  PathNode({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory PathNode.fromJson(Map<String, dynamic> j) =>
      PathNode(id: '${j['id']}', name: '${j['name']}');
}

class ShareInfo {
  ShareInfo({
    required this.url,
    required this.pwd,
    required this.isFile,
    this.name = '',
    this.desc = '',
  });

  final String url;
  final String pwd;
  final bool isFile;
  final String name;
  final String desc;
}

class ShareFileItem {
  ShareFileItem({
    required this.name,
    required this.time,
    required this.size,
    required this.url,
  });

  final String name;
  final String time;
  final String size;
  final String url;
}

class SubFolder {
  SubFolder({required this.name, required this.url, this.desc = ''});

  final String name;
  final String url;
  final String desc;
}

class FolderShareDetail {
  FolderShareDetail({
    required this.name,
    this.desc = '',
    this.sharer = '',
    this.files = const [],
    this.folders = const [],
    this.paging,
    this.hasMore = false,
  });

  final String name;
  final String desc;
  final String sharer;
  /// 当前已加载的文件（默认只有第一页）。
  final List<ShareFileItem> files;
  final List<SubFolder> folders;
  /// 继续分页所需的上下文；为 null 表示这份数据不支持继续加载。
  final ShareFolderPaging? paging;
  /// 是否还有下一页文件（浏览页滑到底再加载）。
  final bool hasMore;
}

/// 分享文件夹的分页上下文：解析分享页后得到，后续页由
/// `LanzouClient.fetchShareFolderFiles` 拉取（与网盘页一致，滑到底再加载）。
class ShareFolderPaging {
  ShareFolderPaging({
    required this.base,
    required this.referer,
    required this.fid,
    required this.lx,
    required this.t,
    required this.k,
    this.uid,
    this.puid,
    this.pwd = '',
  });

  final String base;
  final String referer;
  final String fid;
  final String lx;
  final String t;
  final String k;
  final String? uid;
  final String? puid;
  final String pwd;
}

class DirectFile {
  DirectFile({
    required this.name,
    required this.url,
    this.size = '',
    this.desc = '',
    this.sharer = '',
  });

  final String name;
  final String url;
  final String size;
  final String desc;
  final String sharer;
}
