import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/account_data.dart';

void main() {
  test('按账号分组：结构与示例一致，分组按账号排序', () {
    final grouped = groupByAccount([
      {'id': 71, 'account': '556911', 'name': '蓝云图标包', 'ref': '3990616'},
      {'id': 66, 'account': '523441', 'name': '测试目录', 'ref': '1'},
      {'id': 75, 'account': '556911', 'name': '空文件夹', 'ref': '359289'},
    ]);

    expect(grouped['data_version'], '1');
    final groups = grouped['data'] as List;
    expect(groups.map((g) => (g as Map)['account']), ['523441', '556911']);
    final first = (groups[1] as Map)['data'] as List;
    expect(first.length, 2);
    expect((first[0] as Map)['ref'], '3990616');
    expect((first[1] as Map)['ref'], '359289');
    // 账号已在分组上，行内不再重复保存
    expect((first[0] as Map).containsKey('account'), isFalse);
    expect((first[1] as Map).containsKey('account'), isFalse);
  });

  test('读取分组格式：行内没有 account 时用分组账号补齐', () {
    final rows = rowsOfAccountData({
      'data_version': '1',
      'data': [
        {
          'account': '556911',
          'data': [
            {'id': 71, 'name': '蓝云图标包', 'ref': '3990616'},
            {'id': 75, 'account': '556911', 'name': '空文件夹', 'ref': '359289'},
          ],
        },
      ],
    });

    expect(rows.length, 2);
    expect(rows[0]['account'], '556911');
    expect(rows[1]['name'], '空文件夹');
  });

  test('读取旧格式（平铺数组）', () {
    final rows = rowsOfAccountData([
      {'id': 1, 'account': '556911', 'name': '旧数据', 'ref': '9'},
    ]);

    expect(rows.length, 1);
    expect(rows.first['account'], '556911');
  });

  test('空数据与非法数据都返回空列表', () {
    expect(rowsOfAccountData(null), isEmpty);
    expect(rowsOfAccountData('nonsense'), isEmpty);
    expect(rowsOfAccountData({'data_version': '1', 'data': []}), isEmpty);
  });
}
