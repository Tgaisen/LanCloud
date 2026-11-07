import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/drive_page.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 空目录，不打网络。
class _FakeClient extends LanzouClient {
  _FakeClient() : super(uid: '1');

  final List<String> requestedFolders = [];

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async {
    requestedFolders.add(folderId);
    return (
      folders: const <LzFolder>[],
      path: folderId == '-1'
          ? const <PathNode>[]
          : <PathNode>[PathNode(id: folderId, name: '子目录')],
    );
  }
}

Future<Future<FolderPickResult?>> pumpPicker(
  WidgetTester tester, {
  String? initialName,
  String initialFolderId = '-1',
  _FakeClient? client,
}) async {
  late Future<FolderPickResult?> result;
  final pickerClient = client ?? _FakeClient();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                result = showFolderPicker(
                  context,
                  client: pickerClient,
                  confirmLabel: '上传到此',
                  initialName: initialName,
                  initialFolderId: initialFolderId,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return result;
}

void main() {
  testWidgets('上传到文件夹：名称为空点「上传到此」→ 原地 error state，弹窗不关', (tester) async {
    await pumpPicker(tester, initialName: 'a.zip');
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('上传到此'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('请输入名称'), findsOneWidget);
    // 尾部红色 fill 风格 Error 图标
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byType(FolderPickerDialog), findsOneWidget);
  });

  testWidgets('上传到文件夹：改名后确认返回新文件名', (tester) async {
    final result = await pumpPicker(tester, initialName: 'a.zip');
    await tester.enterText(find.byType(TextField), 'b.zip');
    await tester.tap(find.text('上传到此'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect((await result)?.fileName, 'b.zip');
  });

  testWidgets('移动模式（没有名称输入框）：不会误报名称错误', (tester) async {
    final result = await pumpPicker(tester, initialName: null);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('上传到此'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('请输入名称'), findsNothing);
    expect((await result)?.fileName, isNull);
  });

  testWidgets('指定初始目录时直接加载该目录，供修改上传目录复用', (tester) async {
    final client = _FakeClient();
    await pumpPicker(tester, initialFolderId: 'child', client: client);

    expect(client.requestedFolders, ['child']);
    expect(find.text('子目录'), findsOneWidget);
  });
}
