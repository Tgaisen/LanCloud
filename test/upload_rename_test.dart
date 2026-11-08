import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/rename_rule.dart';

void main() {
  const targets = [
    RenameTarget(id: 'a', name: 'Photo_One.PNG'),
    RenameTarget(id: 'b', name: 'Photo_Two.PNG'),
  ];

  test('普通文本默认替换全部匹配项且区分大小写', () {
    final preview = const BatchRenameRule(
      search: 'Photo',
      replacement: 'Image',
      useRegex: false,
      matchCase: true,
    ).preview(targets);

    expect(preview.error, isNull);
    expect(preview.changes.map((change) => change.newName), [
      'Image_One.PNG',
      'Image_Two.PNG',
    ]);
  });

  test('普通文本关闭区分大小写后忽略大小写替换', () {
    final preview = const BatchRenameRule(
      search: 'photo',
      replacement: 'image',
      useRegex: false,
      matchCase: false,
    ).preview(targets);

    expect(preview.error, isNull);
    expect(preview.changes.map((change) => change.newName), [
      'image_One.PNG',
      'image_Two.PNG',
    ]);
  });

  test('正则表达式支持捕获组替换', () {
    final preview = const BatchRenameRule(
      search: r'^(Photo)_(One|Two)(\.PNG)$',
      replacement: r'$2-$1$3',
      useRegex: true,
      matchCase: true,
    ).preview(targets);

    expect(preview.error, isNull);
    expect(preview.changes.map((change) => change.newName), [
      'One-Photo.PNG',
      'Two-Photo.PNG',
    ]);
  });

  test('无效正则、无匹配和空名称会阻止应用', () {
    expect(
      const BatchRenameRule(
        search: '[',
        replacement: '',
        useRegex: true,
        matchCase: false,
      ).preview(targets).error,
      RenameError.invalidPattern,
    );
    expect(
      const BatchRenameRule(
        search: 'not-found',
        replacement: '',
        useRegex: false,
        matchCase: false,
      ).preview(targets).error,
      RenameError.noMatches,
    );
    expect(
      const BatchRenameRule(
        search: 'Photo_One.PNG',
        replacement: '   ',
        useRegex: false,
        matchCase: false,
      ).preview(targets).error,
      RenameError.emptyName,
    );
  });

  test('允许修改后与同批其他任务同名', () {
    const collisions = [
      RenameTarget(id: 'a', name: 'old.zip'),
      RenameTarget(id: 'b', name: 'target.zip'),
    ];
    final preview = const BatchRenameRule(
      search: 'old',
      replacement: 'target',
      useRegex: false,
      matchCase: false,
    ).preview(collisions);

    expect(preview.error, isNull);
    expect(preview.changes.single.newName, 'target.zip');
  });
}
