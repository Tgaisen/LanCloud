import 'dart:convert';

/// 收藏分享项最近一次可确认的访问状态。
///
/// 网络错误和页面解析失败不会写入这里，避免一次临时异常把收藏批量标成失效。
enum FavoriteShareStatus { unchecked, valid, unavailable, passwordChanged }

FavoriteShareStatus favoriteShareStatusFromName(Object? value) {
  final name = '${value ?? ''}';
  return FavoriteShareStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => FavoriteShareStatus.unchecked,
  );
}

extension FavoriteShareStatusX on FavoriteShareStatus {
  /// 是否可以继续参与更新 badge 统计。
  bool get accessible =>
      this == FavoriteShareStatus.unchecked ||
      this == FavoriteShareStatus.valid;
}

/// 收藏文件夹第一页首个文件的稳定指纹。
class FavoriteFolderHead {
  const FavoriteFolderHead({
    required this.remoteId,
    required this.name,
    required this.time,
    required this.size,
  });

  final String remoteId;
  final String name;
  final String time;
  final String size;

  bool sameAs(FavoriteFolderHead other) =>
      remoteId == other.remoteId &&
      name == other.name &&
      time == other.time &&
      size == other.size;

  Map<String, Object?> toJson() => {
    'remoteId': remoteId,
    'name': name,
    'time': time,
    'size': size,
  };

  static FavoriteFolderHead? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final remoteId = value['remoteId'];
    final name = value['name'];
    final time = value['time'];
    final size = value['size'];
    if (remoteId is! String || name is! String) return null;
    return FavoriteFolderHead(
      remoteId: remoteId,
      name: name,
      time: time is String ? time : '',
      size: size is String ? size : '',
    );
  }
}

/// 一个收藏文件夹的无分页快照。
///
/// 只需要首项或“空文件夹”两种状态；蓝奏云默认把新文件排在前面，因此首项
/// 变化即可表示分享者做过修改。
sealed class FavoriteFolderSnapshot {
  const FavoriteFolderSnapshot({required this.checkedAt});

  final int checkedAt;

  bool sameAs(FavoriteFolderSnapshot other) => switch ((this, other)) {
    (EmptyFavoriteFolderSnapshot(), EmptyFavoriteFolderSnapshot()) => true,
    (
      HeadFavoriteFolderSnapshot(head: final left),
      HeadFavoriteFolderSnapshot(head: final right),
    ) =>
      left.sameAs(right),
    _ => false,
  };

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  static FavoriteFolderSnapshot? tryDecode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final checkedAt = value['checkedAt'];
      if (checkedAt is! int) return null;
      switch (value['state']) {
        case 'empty':
          return EmptyFavoriteFolderSnapshot(checkedAt: checkedAt);
        case 'head':
          final head = FavoriteFolderHead.tryFromJson(value['head']);
          return head == null
              ? null
              : HeadFavoriteFolderSnapshot(head: head, checkedAt: checkedAt);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

final class EmptyFavoriteFolderSnapshot extends FavoriteFolderSnapshot {
  const EmptyFavoriteFolderSnapshot({required super.checkedAt});

  @override
  Map<String, Object?> toJson() => {'state': 'empty', 'checkedAt': checkedAt};
}

final class HeadFavoriteFolderSnapshot extends FavoriteFolderSnapshot {
  const HeadFavoriteFolderSnapshot({
    required this.head,
    required super.checkedAt,
  });

  final FavoriteFolderHead head;

  @override
  Map<String, Object?> toJson() => {
    'state': 'head',
    'checkedAt': checkedAt,
    'head': head.toJson(),
  };
}

/// 返回本次检查是否应设置“有更新”。
///
/// 没有旧快照时只建立基线；空/非空互相变化以及首项指纹变化都算更新。
bool favoriteFolderHasChanged(
  FavoriteFolderSnapshot? previous,
  FavoriteFolderSnapshot current,
) => previous != null && !previous.sameAs(current);
