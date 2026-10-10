import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/models.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/data/account_store.dart';
import 'package:lancloud/core/drive_cache.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart' as app_icons;
import 'package:lancloud/ui/common.dart';
import 'package:lancloud/ui/drive_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网盘页挂载在目录缓存上（不进网络）：给个账号让 `app.client` 非空，
/// 再塞一份根目录快照，`_load()` 直接命中缓存。
Future<void> host(WidgetTester tester, {required bool grid}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppController();
  app.accounts.accounts = [Account(uid: '1', cookie: 'cookie')];
  app.accounts.activeUid = '1';
  app.settings.gridView = grid;
  app.driveCache.put(
    '-1',
    CachedFolder(
      folders: [LzFolder(id: 'f1', name: '测试文件夹', desc: '')],
      files: [LzFile(id: 'l1', name: '测试文件.zip', size: '1M', time: '')],
      path: const [],
      page: 1,
      hasMore: false,
    ),
  );
  final manager = TransferManager(app);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<TransferManager>.value(value: manager),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const DrivePage(tabIndex: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 图标块（[Icon] 外面那层圆角容器）的底色。
Color? boxColorOf(WidgetTester tester, IconData icon) {
  final box = tester.widget<Container>(
    find
        .ancestor(of: find.byIcon(icon).first, matching: find.byType(Container))
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  // 分类覆盖蓝奏云允许上传的全部类型（其余落到 other）。
  const expected = <String, FileKind>{
    'pdf': FileKind.pdf,
    'doc': FileKind.document,
    'docx': FileKind.document,
    'xmind': FileKind.document,
    'epub': FileKind.ebook,
    'mobi': FileKind.ebook,
    'azw': FileKind.ebook,
    'azw3': FileKind.ebook,
    'xls': FileKind.spreadsheet,
    'xlsx': FileKind.spreadsheet,
    'accdb': FileKind.spreadsheet,
    'db': FileKind.spreadsheet,
    'ppt': FileKind.presentation,
    'pptx': FileKind.presentation,
    'txt': FileKind.text,
    'cfg': FileKind.text,
    'conf': FileKind.text,
    'bat': FileKind.code,
    'lua': FileKind.code,
    'jar': FileKind.code,
    'png': FileKind.image,
    'jpeg': FileKind.image,
    'jpg': FileKind.image,
    'gif': FileKind.image,
    'webp': FileKind.image,
    'brushset': FileKind.image,
    'mp3': FileKind.audio,
    'flac': FileKind.audio,
    'mp4': FileKind.video,
    'avi': FileKind.video,
    'zip': FileKind.archive,
    'rar': FileKind.archive,
    '7z': FileKind.archive,
    'tar': FileKind.archive,
    'osz': FileKind.archive,
    'osk': FileKind.archive,
    'rp': FileKind.archive,
    'rplib': FileKind.archive,
    'iso': FileKind.disc,
    'img': FileKind.disc,
    'gho': FileKind.disc,
    'dmg': FileKind.disc,
    'apk': FileKind.android,
    'xapk': FileKind.android,
    'exe': FileKind.executable,
    'dll': FileKind.executable,
    'crx': FileKind.executable,
    'imazingapp': FileKind.executable,
    'deb': FileKind.executable,
    'appimage': FileKind.executable,
    'pkg': FileKind.executable,
    'ttf': FileKind.font,
    'ttc': FileKind.font,
    'txf': FileKind.font,
    // 罕见的专有格式：统一用默认灰
    'w3x': FileKind.other,
    'xpa': FileKind.other,
    'cpk': FileKind.other,
    'lolgezi': FileKind.other,
    'cad': FileKind.other,
    'dwg': FileKind.other,
    'hwt': FileKind.other,
    'ce': FileKind.other,
    'cetrainer': FileKind.other,
    'ct': FileKind.other,
    'ke': FileKind.other,
    'e': FileKind.other,
    'z': FileKind.other,
    'it': FileKind.other,
    'ssf': FileKind.other,
    'bds': FileKind.other,
    'bdi': FileKind.other,
    'enc': FileKind.other,
    'mobileconfig': FileKind.other,
  };

  test('扩展名 → 文件分类', () {
    expected.forEach((ext, kind) {
      expect(fileKindFor('文件.$ext'), kind, reason: ext);
      // 大小写不敏感
      expect(fileKindFor('文件.${ext.toUpperCase()}'), kind, reason: ext);
    });
    expect(fileKindFor('没有扩展名'), FileKind.other);
    expect(fileKindFor('.gitignore'), FileKind.other, reason: '点开头不算扩展名');
  });

  test('图标沿用原有形状：pdf / 文档 / 表格 / 演示 / 压缩包 / 安装包', () {
    expect(iconForFile('a.pdf'), app_icons.Icons.picture_as_pdf_outlined);
    expect(iconForFile('a.docx'), app_icons.Icons.description_outlined);
    expect(iconForFile('a.xlsx'), app_icons.Icons.table_chart_outlined);
    expect(iconForFile('a.pptx'), app_icons.Icons.slideshow_outlined);
    expect(iconForFile('a.zip'), app_icons.Icons.folder_zip_outlined);
    expect(iconForFile('a.7z'), app_icons.Icons.folder_zip_outlined);
    expect(iconForFile('a.apk'), app_icons.Icons.android_outlined);
    expect(iconForFile('a.exe'), app_icons.Icons.window_outlined);
    expect(iconForFile('a.png'), app_icons.Icons.image_outlined);
    expect(iconForFile('a.mp4'), app_icons.Icons.movie_outlined);
    expect(iconForFile('a.mp3'), app_icons.Icons.music_note_outlined);
    expect(iconForFile('a.epub'), app_icons.Icons.menu_book_outlined);
    expect(iconForFile('a.dart'), app_icons.Icons.code_outlined);
    expect(iconForFile('a.iso'), app_icons.Icons.album_outlined);
    expect(iconForFile('a.ttf'), app_icons.Icons.font_download_outlined);
    expect(iconForFile('无扩展名'), app_icons.Icons.insert_drive_file_outlined);
  });

  test('每个分类一种颜色，深浅色都有对比', () {
    final kinds = FileKind.values.where((k) => k != FileKind.ebook).toList();
    final colors = kinds.map((k) => fileKindColor(k)).toList();
    // 电子书与文档同色（都是文档类），其余两两不同
    expect(colors.toSet().length, colors.length);
    expect(
      fileKindColor(FileKind.ebook),
      fileKindColor(FileKind.document),
      reason: '电子书沿用文档蓝',
    );

    for (final kind in FileKind.values) {
      final light = fileKindColor(kind);
      final dark = fileKindColor(kind, brightness: Brightness.dark);
      expect(
        dark.computeLuminance(),
        greaterThan(light.computeLuminance()),
        reason: '$kind 深色主题下应更亮',
      );
    }
  });

  testWidgets('Md3ListItem：图标颜色可定制', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Md3ListItem(
            icon: app_icons.Icons.folder,
            iconColor: const Color(0xFF123456),
            title: '文件夹',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(app_icons.Icons.folder));
    // 文件夹不再用实心图标：与文件一样是描边
    expect(icon.fill ?? 0, 0);
    expect(icon.color, const Color(0xFF123456));
  });

  testWidgets('属性弹窗头部：图标块与列表项同款（42 / 圆角 12 / 图标 22）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6BE6)),
        ),
        home: Scaffold(
          // 文件夹：主题强调色 + 与列表项一致的图标块
          body: const PropertyHeaderCard(
            icon: app_icons.Icons.folder,
            title: '文件夹',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.byType(PropertyHeaderCard)))
        .colorScheme;
    final icon = tester.widget<Icon>(find.byIcon(app_icons.Icons.folder));
    expect(icon.size, 22);
    expect(icon.fill ?? 0, 0);
    expect(icon.color, scheme.primary);

    final box = find
        .ancestor(
          of: find.byIcon(app_icons.Icons.folder),
          matching: find.byType(Container),
        )
        .first;
    expect(tester.getSize(box), const Size(42, 42));
    final decoration =
        tester.widget<Container>(box).decoration! as BoxDecoration;
    expect(decoration.color, scheme.surfaceContainerHigh);
    expect(decoration.borderRadius, BorderRadius.circular(12));

    // 卡片底色与列表项（Md3ListItem）的容器一致
    final card = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(PropertyHeaderCard),
            matching: find.byType(Container),
          ),
        )
        .firstWhere(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(24),
        );
    expect((card.decoration! as BoxDecoration).color, scheme.surfaceContainer);
  });

  testWidgets('属性弹窗头部：文件按类型着色，底块与网盘页文件一致', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6BE6)),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => PropertyHeaderCard(
              icon: iconForFile('报告.pdf'),
              iconColor: fileIconColor(
                '报告.pdf',
                brightness: Theme.of(context).colorScheme.brightness,
              ),
              title: '报告.pdf',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.byType(PropertyHeaderCard)))
        .colorScheme;
    final icon = tester.widget<Icon>(
      find.byIcon(app_icons.Icons.picture_as_pdf_outlined),
    );
    expect(icon.color, fileIconColor('报告.pdf'));
    expect(icon.fill ?? 0, 0);
    expect(
      boxColorOf(tester, app_icons.Icons.picture_as_pdf_outlined),
      scheme.surfaceContainerHigh,
    );
  });

  testWidgets('网盘页网格：文件夹主题色描边，图标块与文件同款', (tester) async {
    await host(tester, grid: true);
    final scheme = Theme.of(tester.element(find.byType(DrivePage))).colorScheme;

    // 文件夹：主题强调色 + 与文件一样的描边风格
    final folder = tester.widget<Icon>(
      find.byIcon(app_icons.Icons.folder).first,
    );
    expect(folder.fill ?? 0, 0);
    expect(folder.color, scheme.primary);
    expect(
      boxColorOf(tester, app_icons.Icons.folder),
      scheme.surfaceContainerHigh,
    );

    // 文件：按类型着色，图标块与文件夹一致
    final file = tester.widget<Icon>(
      find.byIcon(app_icons.Icons.folder_zip_outlined).first,
    );
    // 文件图标不设定填充轴，沿用主题的 fill: 0（描边）
    expect(file.fill ?? 0, 0);
    expect(file.color, fileIconColor('测试文件.zip'));
    expect(
      boxColorOf(tester, app_icons.Icons.folder_zip_outlined),
      scheme.surfaceContainerHigh,
    );

    // 网格卡片底色跟随列表项（Md3ListItem）的底色
    final card = tester.widget<Card>(
      find
          .ancestor(
            of: find.byIcon(app_icons.Icons.folder),
            matching: find.byType(Card),
          )
          .first,
    );
    expect(card.color, scheme.surfaceContainerLow);
  });

  testWidgets('网盘页列表：文件夹 / 文件图标块同底色', (tester) async {
    await host(tester, grid: false);
    final scheme = Theme.of(tester.element(find.byType(DrivePage))).colorScheme;

    final folder = tester.widget<Icon>(
      find.byIcon(app_icons.Icons.folder).first,
    );
    expect(folder.fill ?? 0, 0);
    expect(folder.color, scheme.primary);
    expect(
      boxColorOf(tester, app_icons.Icons.folder),
      scheme.surfaceContainerHigh,
    );

    final file = tester.widget<Icon>(
      find.byIcon(app_icons.Icons.folder_zip_outlined).first,
    );
    expect(file.color, fileIconColor('测试文件.zip'));
    expect(
      boxColorOf(tester, app_icons.Icons.folder_zip_outlined),
      scheme.surfaceContainerHigh,
    );
  });
}
