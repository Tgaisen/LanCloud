import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('SectionHeader', () {
    testWidgets(
      'should match the stable light golden',
      // 基准图由 Windows 生成，跨平台 CI 留到独立 golden job 接入。
      skip: !Platform.isWindows,
      (tester) async {
        tester.view
          ..physicalSize = const Size(420, 96)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final theme = buildLanCloudTheme(
          brightness: Brightness.light,
          seed: LanCloudApp.seed,
          oledDark: false,
        );
        const goldenKey = ValueKey<String>('section-header-golden');

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: goldenKey,
                  child: SizedBox(
                    width: 420,
                    height: 96,
                    child: ColoredBox(
                      color: theme.colorScheme.surface,
                      child: SectionHeader(
                        title: '最近使用',
                        count: 12,
                        actions: [
                          TextButton(onPressed: () {}, child: const Text('整理')),
                          TextButton(onPressed: () {}, child: const Text('全部')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/section_header_light.png'),
        );
      },
    );
  });
}
