/// 按账号分组的数据（快速访问 / 最近使用）在备份里的格式版本。
const String accountDataVersion = '1';

/// 把带 account 字段的行按账号分组：
/// `{data_version: "1", data: [{account: "556911", data: [...]}, ...]}`
Map<String, Object?> groupByAccount(List<Map<String, Object?>> rows) {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final row in rows) {
    final account = '${row['account'] ?? ''}';
    // 账号已经写在分组上，行内不再重复保存
    final data = {...row}..remove('account');
    groups.putIfAbsent(account, () => []).add(data);
  }
  final accounts = groups.keys.toList()..sort();
  return {
    'data_version': accountDataVersion,
    'data': [
      for (final account in accounts)
        {
          'account': account,
          'data': groups[account],
        },
    ],
  };
}

/// 读取按账号分组的数据；同时兼容早期版本的平铺数组。
///
/// 分组里的行如果缺少 account 字段，会用所在分组的账号补齐。
List<Map<String, Object?>> rowsOfAccountData(Object? raw) {
  if (raw is List) {
    return [
      for (final row in raw)
        if (row is Map) row.cast<String, Object?>(),
    ];
  }
  if (raw is Map) {
    final out = <Map<String, Object?>>[];
    for (final group in (raw['data'] as List? ?? const [])) {
      if (group is! Map) continue;
      final account = '${group['account'] ?? ''}';
      for (final row in (group['data'] as List? ?? const [])) {
        if (row is! Map) continue;
        final map = row.cast<String, Object?>();
        out.add({...map, if (!map.containsKey('account')) 'account': account});
      }
    }
    return out;
  }
  return const [];
}
