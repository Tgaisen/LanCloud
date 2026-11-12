import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/list_home_settings_state.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:lancloud/ui/m3e.dart';

import 'package:lancloud/l10n/delegates.dart';

/// 返回固定目录，不打网络。
class _FakeClient extends LanzouClient {
  _FakeClient({this.folders = const <LzFolder>[]}) : super(uid: '1');

  final List<String> requestedFolders = [];
  final List<LzFolder> folders;

  @override
  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async {
    requestedFolders.add(folderId);
    return (
      folders: folders,
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
  LanzouClient? client,
  ListHomeSettingsState? sortSettings,
}) async {
  late Future<FolderPickResult?> result;
  final pickerClient = client ?? _FakeClient();
  final pickerSortSettings =
      sortSettings ?? ListHomeSettingsState(SettingsStore());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        listHomeSettingsStateProvider.overrideWithValue(pickerSortSettings),
      ],
      child: MaterialApp(
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

  testWidgets('弹窗使用本地时间升序，并可切换到名称排序', (tester) async {
    final sortSettings = ListHomeSettingsState(SettingsStore());
    final client = _FakeClient(
      folders: [
        LzFolder(id: 'z', name: 'Zulu', desc: ''),
        LzFolder(id: 'b', name: 'Banana', desc: ''),
        LzFolder(id: 'a', name: 'Apple', desc: ''),
      ],
    );
    await pumpPicker(tester, client: client, sortSettings: sortSettings);

    final pathBar = tester.widget<PathBar>(find.byType(PathBar));
    expect(pathBar.horizontalPadding, 0);
    expect(find.byType(M3eIconButton), findsNWidgets(2));

    final sortButton = find.byTooltip('排序');
    final newFolderButton = find.byTooltip('新建文件夹');
    expect(sortButton, findsOneWidget);
    expect(newFolderButton, findsOneWidget);
    expect(
      tester
          .widget<M3eIconButton>(
            find
                .ancestor(of: sortButton, matching: find.byType(M3eIconButton))
                .first,
          )
          .containerColor,
      isNull,
    );
    expect(
      tester
          .widget<M3eIconButton>(
            find
                .ancestor(
                  of: newFolderButton,
                  matching: find.byType(M3eIconButton),
                )
                .first,
          )
          .containerColor,
      isNull,
    );
    expect(
      tester.getRect(newFolderButton).left - tester.getRect(sortButton).right,
      4,
      reason: '两个独立图标按钮沿用原路径栏操作之间的 4dp 间距',
    );

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Zulu'), lessThan(top('Banana')));
    expect(top('Banana'), lessThan(top('Apple')));

    final list = tester.widget<SegmentedSliverList>(
      find.byType(SegmentedSliverList),
    );
    final scheme = Theme.of(tester.element(find.byType(PathBar))).colorScheme;
    expect(list.color, scheme.surfaceContainerHighest);
    expect(list.margin, EdgeInsets.zero);

    await tester.tap(sortButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('大小'), findsNothing);
    expect(
      find.byKey(const ValueKey('m3e-menu-selected-check-升序')),
      findsOneWidget,
    );

    await tester.tap(find.text('升序'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(top('Apple'), lessThan(top('Banana')));
    expect(top('Banana'), lessThan(top('Zulu')));

    await tester.tap(sortButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('名称'));
    await tester.pumpAndSettle();
    expect(find.text('时间'), findsNothing);

    await tester.tap(sortButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('升序'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(top('Apple'), lessThan(top('Banana')));
    expect(top('Banana'), lessThan(top('Zulu')));
    expect(sortSettings.folderPickerSortMode, 'name');
    expect(sortSettings.folderPickerSortAscending, isTrue);
  });

  testWidgets('重新打开弹窗沿用已保存的名称升序', (tester) async {
    final sortSettings = ListHomeSettingsState(SettingsStore());
    sortSettings.store.folderPickerSortMode = 'name';
    sortSettings.store.folderPickerSortAscending = true;
    final client = _FakeClient(
      folders: [
        LzFolder(id: 'z', name: 'Zulu', desc: ''),
        LzFolder(id: 'b', name: 'Banana', desc: ''),
        LzFolder(id: 'a', name: 'Apple', desc: ''),
      ],
    );
    await pumpPicker(tester, client: client, sortSettings: sortSettings);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Apple'), lessThan(top('Banana')));
    expect(top('Banana'), lessThan(top('Zulu')));

    await tester.tap(find.byTooltip('排序'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('m3e-menu-selected-check-升序')),
      findsOneWidget,
    );
  });
}
