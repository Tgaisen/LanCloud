import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/app_db.dart';
import 'package:lancloud/l10n/l10n.dart';
import 'package:lancloud/ui/home_page.dart';

PinItem pin(String name, String path) =>
    PinItem(id: 1, account: 'u1', name: name, ref: 'f1', path: path);

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('副标题显示「所在目录」的路径，不含文件夹自身', () {
    expect(quickAccessPathLabel(zh, pin('示例', 'abc')), '根目录/abc');
    expect(quickAccessPathLabel(zh, pin('示例', 'a/b')), '根目录/a/b');
    // 顶层文件夹：所在目录就是根目录
    expect(quickAccessPathLabel(zh, pin('示例', '')), '根目录');
  });

  test('兼容旧数据：剥掉「根目录」前缀与文件夹自身', () {
    expect(
      quickAccessPathLabel(zh, pin('示例', '根目录/abc/示例')),
      '根目录/abc',
    );
    expect(quickAccessPathLabel(zh, pin('示例', '根目录/示例')), '根目录');
    // 旧数据可能是英文界面下固定下来的
    expect(
      quickAccessPathLabel(zh, pin('示例', 'Root/abc/示例')),
      '根目录/abc',
    );
    expect(quickAccessPathLabel(en, pin('Sample', 'Root/Sample')), 'Root');
  });

  test('「根目录」按当前语言显示，切换语言后跟着变', () {
    expect(quickAccessPathLabel(en, pin('示例', 'abc')), 'Root/abc');
    expect(
      quickAccessPathLabel(en, pin('示例', '根目录/abc/示例')),
      'Root/abc',
    );
  });
}
