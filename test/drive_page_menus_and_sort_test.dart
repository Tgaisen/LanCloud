import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/m3e.dart';
// 应用用的是自己的 Symbols 图标集，和框架的 Icons 同名，按应用代码的习惯隐藏后者
import 'package:material_ui/material_ui.dart' hide Icons;

import 'support/drive_property_test_support.dart';

void main() {
  testWidgets('Android 能力下添加菜单包含从其他应用上传', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app);

    await openAddMenu(tester);

    expect(find.text(testZh.uploadFromApp), findsOneWidget);
  });

  testWidgets('Windows 能力下添加菜单隐藏从其他应用上传', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app, capabilities: PlatformCapabilities.windows);

    await openAddMenu(tester);

    expect(find.text(testZh.uploadFromApp), findsNothing);
    expect(find.text(testZh.uploadFile), findsOneWidget);
  });

  testWidgets('iOS 能力下添加菜单隐藏从其他应用上传', (tester) async {
    final app = FakeDriveApp(FakeDriveClient());
    await pumpDrive(tester, app, capabilities: PlatformCapabilities.ios);

    await openAddMenu(tester);

    expect(find.text(testZh.uploadFromApp), findsNothing);
    expect(find.text(testZh.uploadFile), findsOneWidget);
  });

  testWidgets('网盘列表模式在宽窗口下仍保持单列', (tester) async {
    final app = FakeDriveApp(ManyFilesClient());
    app.environment.cachePageSettings.store.gridView = false;
    await pumpDrive(tester, app, viewSize: const Size(1200, 800));

    final first = tester.getTopLeft(find.text('file1.zip'));
    final second = tester.getTopLeft(find.text('file2.zip'));
    final third = tester.getTopLeft(find.text('file3.zip'));
    expect(second.dx, first.dx);
    expect(third.dx, first.dx);
    expect(second.dy, greaterThan(first.dy));
    expect(third.dy, greaterThan(second.dy));
    expect(find.byType(AdaptiveSliverRows), findsNothing);
    expect(
      find.text('${prettyLzSize('1 M')} · 1 天前 · 下载数 5'),
      findsNWidgets(3),
    );
  });

  testWidgets('路径栏 48dp：窄屏用独立排序/视图按钮，宽屏保留连接组', (tester) async {
    final app = FakeDriveApp(OrderedDriveClient());
    app.environment.cachePageSettings.store.gridView = false;
    await pumpDrive(tester, app, viewSize: const Size(320, 800));

    expect(tester.getSize(find.byType(PathBar)).height, 48);
    final titleLeft = tester.getTopLeft(find.text('网盘')).dx;
    final rootLeft = tester
        .getTopLeft(
          find.descendant(of: find.byType(PathBar), matching: find.text('根目录')),
        )
        .dx;
    expect(rootLeft, closeTo(titleLeft, 0.5));
    final sortButton = find.byTooltip('排序');
    final viewButton = find.byTooltip('视图');
    expect(sortButton, findsOneWidget);
    expect(viewButton, findsOneWidget);
    final sortIconButton = tester.widget<M3eIconButton>(
      find.ancestor(of: sortButton, matching: find.byType(M3eIconButton)).first,
    );
    final viewIconButton = tester.widget<M3eIconButton>(
      find.ancestor(of: viewButton, matching: find.byType(M3eIconButton)).first,
    );
    expect(sortIconButton.containerColor, isNull);
    expect(viewIconButton.containerColor, isNull);
    expect(
      tester.getSize(sortButton),
      const Size(48, 48),
      reason: '路径栏和图标按钮均使用 48dp 触控目标',
    );
    expect(tester.getSize(viewButton), const Size(48, 48));
    expect(
      tester.getRect(viewButton).left - tester.getRect(sortButton).right,
      0,
      reason: '小屏路径栏按钮与 AppBar actions 一样相邻无额外间距',
    );
    expect(
      tester.getRect(viewButton).right,
      closeTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
        0.5,
      ),
      reason: '小屏路径栏最后一个按钮与 AppBar actions 一样贴右边缘',
    );
    expect(find.byType(M3eConnectedButtonGroup<String>), findsNothing);

    await tester.tap(viewButton);
    await settleSheet(tester);
    expect(find.text('列表视图'), findsOneWidget);
    expect(find.text('网格视图'), findsOneWidget);
    await tester.tap(find.text('网格视图'));
    await settleSheet(tester);
    expect(app.environment.cachePageSettings.store.gridView, isTrue);

    tester.view.physicalSize = const Size(800, 800);
    await tester.pumpAndSettle();
    final layoutGroup = find.byType(M3eConnectedButtonGroup<String>);
    expect(layoutGroup, findsOneWidget);
    expect(tester.getSize(layoutGroup).width, 98);
    expect(
      find
          .descendant(of: layoutGroup, matching: find.text('网格视图'))
          .hitTestable(),
      findsNothing,
      reason: '连接组只显示图标；读屏文字不参与视觉显示',
    );
    expect(find.byTooltip('列表视图'), findsOneWidget);
    expect(find.byTooltip('网格视图'), findsOneWidget);
  });

  testWidgets('排序升降序：文件夹时间反转、大小与下载数保持原序', (tester) async {
    final app = FakeDriveApp(OrderedDriveClient());
    app.environment.cachePageSettings.store.gridView = false;
    await pumpDrive(tester, app, viewSize: const Size(420, 900));

    Future<void> openSort() async {
      await tester.tap(find.byTooltip('排序'));
      await settleSheet(tester);
    }

    Future<void> closeSort() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    double top(String text) => tester.getTopLeft(find.text(text)).dy;

    // 服务端按时间早到晚返回；默认“时间 + 升序”保持原顺序。
    expect(top('文件夹 B'), lessThan(top('文件夹 A')));
    expect(top('文件夹 A'), lessThan(top('文件夹 C')));
    expect(top('a.zip'), lessThan(top('b.zip')));
    expect(top('b.zip'), lessThan(top('c.zip')));

    await openSort();
    expect(find.byType(Radio<bool>), findsNWidgets(4));
    expect(find.text('大小'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('大小')).dy,
      lessThan(tester.getTopLeft(find.text('下载数')).dy),
    );
    final downloadTile = tester.widget<M3ePickTile>(
      find.ancestor(of: find.text('下载数'), matching: find.byType(M3ePickTile)),
    );
    expect(
      downloadTile.leading,
      isA<Icon>().having((icon) => icon.icon, 'icon', Icons.download),
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.text('升序'));
    await tester.pump();
    await closeSort();

    expect(top('文件夹 C'), lessThan(top('文件夹 A')));
    expect(top('文件夹 A'), lessThan(top('文件夹 B')));
    expect(top('c.zip'), lessThan(top('b.zip')));
    expect(top('b.zip'), lessThan(top('a.zip')));

    await openSort();
    await tester.tap(find.text('升序'));
    await tester.pump();
    await tester.tap(find.text('大小'));
    await tester.pumpAndSettle();
    expect(find.text('时间'), findsNothing);

    // 大小无法比较文件夹：保持服务端原顺序；文件按 1M / 2M / 3M 升序。
    expect(top('文件夹 B'), lessThan(top('文件夹 A')));
    expect(top('文件夹 A'), lessThan(top('文件夹 C')));
    expect(top('c.zip'), lessThan(top('b.zip')));
    expect(top('b.zip'), lessThan(top('a.zip')));

    await openSort();
    await tester.tap(find.text('下载数'));
    await tester.pumpAndSettle();

    // 下载数也不适用于文件夹：仍保持服务端原顺序；文件按 1 / 2 / 3 升序。
    expect(top('文件夹 B'), lessThan(top('文件夹 A')));
    expect(top('文件夹 A'), lessThan(top('文件夹 C')));
    expect(top('a.zip'), lessThan(top('c.zip')));
    expect(top('c.zip'), lessThan(top('b.zip')));
  });
}
