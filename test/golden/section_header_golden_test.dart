import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('SectionHeader', () {
    testWidgets('should match the stable light golden', (tester) async {
      await _expectSectionHeaderGolden(
        tester,
        brightness: Brightness.light,
        goldenFile: 'goldens/section_header_light.png',
      );
    }, skip: !Platform.isWindows);

    testWidgets('should match the stable dark golden', (tester) async {
      await _expectSectionHeaderGolden(
        tester,
        brightness: Brightness.dark,
        goldenFile: 'goldens/section_header_dark.png',
      );
    }, skip: !Platform.isWindows);
  });
}

Future<void> _expectSectionHeaderGolden(
  WidgetTester tester, {
  required Brightness brightness,
  required String goldenFile,
}) async {
  tester.view
    ..physicalSize = const Size(420, 96)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = buildLanCloudTheme(
    brightness: brightness,
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

  await expectLater(find.byKey(goldenKey), matchesGoldenFile(goldenFile));
}
