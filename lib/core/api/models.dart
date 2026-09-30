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
        hasPwd: '${j['onof'] ?? 0}' == '1',
        hasDes: '${j['is_des'] ?? 0}' == '1',
      );
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
        id: '${j['fol_id']}',
        name: '${j['name'] ?? ''}',
        desc: '${j['folder_des'] ?? ''}'.replaceAll('[', '').replaceAll(']', '').trim(),
        hasPwd: '${j['onof'] ?? 0}' == '1',
      );
}

class PathNode {
  PathNode({required this.id, required this.name});

  final String id;
  final String name;
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
    this.files = const [],
    this.folders = const [],
  });

  final String name;
  final String desc;
  final List<ShareFileItem> files;
  final List<SubFolder> folders;
}

class DirectFile {
  DirectFile({required this.name, required this.url, this.size = ''});

  final String name;
  final String url;
  final String size;
}
