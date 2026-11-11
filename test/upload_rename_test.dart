import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/rename_rule.dart';

void main() {
  const targets = [
    RenameTarget(id: 'a', name: 'Photo_One.PNG', kind: RenameTargetKind.file),
    RenameTarget(id: 'b', name: 'Photo_Two.PNG', kind: RenameTargetKind.file),
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
      RenameTarget(id: 'a', name: 'old.zip', kind: RenameTargetKind.file),
      RenameTarget(id: 'b', name: 'target.zip', kind: RenameTargetKind.file),
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

  test('文件名允许冒号、星号、问号、竖线和空格，拒绝文件非法字符', () {
    for (final name in ['a:b*c?d|e f.zip', '中文名称.zip']) {
      expect(
        containsInvalidRenameCharacters(name, RenameTargetKind.file),
        isFalse,
        reason: name,
      );
    }
    for (final character in ['\\', '/', '"', '<', '>']) {
      expect(
        containsInvalidRenameCharacters(
          'file${character}name.zip',
          RenameTargetKind.file,
        ),
        isTrue,
        reason: character,
      );
    }
  });

  test('文件夹名拒绝文件额外字符和空格', () {
    expect(
      containsInvalidRenameCharacters('中文文件夹', RenameTargetKind.folder),
      isFalse,
    );
    for (final character in [
      '\\',
      '/',
      ':',
      '*',
      '?',
      '"',
      '<',
      '>',
      '|',
      ' ',
    ]) {
      expect(
        containsInvalidRenameCharacters(
          'folder${character}name',
          RenameTargetKind.folder,
        ),
        isTrue,
        reason: character,
      );
    }
  });

  test('批量全部为文件时允许文件专属字符', () {
    const fileTargets = [
      RenameTarget(id: 'a', name: 'old1.zip', kind: RenameTargetKind.file),
      RenameTarget(id: 'b', name: 'old2.zip', kind: RenameTargetKind.file),
    ];
    final preview = const BatchRenameRule(
      search: 'old',
      replacement: 'new:*?| ',
      useRegex: false,
      matchCase: false,
    ).preview(fileTargets);

    expect(preview.error, isNull);
    expect(preview.changes.map((change) => change.newName), [
      'new:*?| 1.zip',
      'new:*?| 2.zip',
    ]);
  });

  test('批量全部为文件夹时使用文件夹规则', () {
    const folderTargets = [
      RenameTarget(id: 'a', name: 'old-one', kind: RenameTargetKind.folder),
      RenameTarget(id: 'b', name: 'old-two', kind: RenameTargetKind.folder),
    ];
    final preview = const BatchRenameRule(
      search: 'old',
      replacement: 'new name',
      useRegex: false,
      matchCase: false,
    ).preview(folderTargets);

    expect(preview.error, RenameError.invalidCharacters);
    expect(preview.changes, isEmpty);
  });

  test('批量混合文件和文件夹时按文件夹规则校验', () {
    const mixedTargets = [
      RenameTarget(id: 'f', name: 'old.zip', kind: RenameTargetKind.file),
      RenameTarget(id: 'd', name: 'old-folder', kind: RenameTargetKind.folder),
    ];
    for (final replacement in ['new name', 'new:name']) {
      final preview = BatchRenameRule(
        search: 'old',
        replacement: replacement,
        useRegex: false,
        matchCase: false,
      ).preview(mixedTargets);

      expect(preview.error, RenameError.invalidCharacters, reason: replacement);
      expect(preview.changes, isEmpty);
    }
  });

  test('批量只校验实际发生变化的新名称', () {
    const targetsWithExistingSpace = [
      RenameTarget(id: 'a', name: 'old.zip', kind: RenameTargetKind.file),
      RenameTarget(
        id: 'b',
        name: 'existing folder',
        kind: RenameTargetKind.folder,
      ),
    ];
    final preview = const BatchRenameRule(
      search: 'old.zip',
      replacement: 'new.zip',
      useRegex: false,
      matchCase: false,
    ).preview(targetsWithExistingSpace);

    expect(preview.error, isNull);
    expect(preview.changes.single.newName, 'new.zip');
  });
}
