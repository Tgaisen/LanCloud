import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/share_file_sheet.dart';
import 'package:provider/provider.dart';

import 'package:lancloud/l10n/delegates.dart';

void main() {
  // 分享文件夹浏览页里点文件弹出的这张表就是「项目菜单」：只留下载 / 复制链接 /
  // 二维码 / 收藏，「打开链接」按需求去掉（浏览器的入口在别处）。
  testWidgets('分享文件属性弹窗：没有「打开链接」，其余入口都在', (tester) async {
    final app = AppController();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider<AppController>.value(value: app)],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            // 已知失效：跳过链接解析，不依赖网络
            body: ShareFileInfoSheet(
              name: 'a.zip',
              url: 'https://example.com/abcdef',
              pwd: '',
              size: '1 MB',
              invalid: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('打开链接'), findsNothing);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.text('显示二维码'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
  });
}
