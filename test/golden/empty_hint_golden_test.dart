import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/l10n/delegates.dart';
import 'package:lancloud/ui/app_icons.dart';
import 'package:lancloud/ui/common.dart';
import 'package:material_ui/material_ui.dart' hide Icons;

void main() {
  group('EmptyHint', () {
    testWidgets('should match the stable light golden', (tester) async {
      await _expectEmptyHintGolden(
        tester,
        brightness: Brightness.light,
        goldenFile: 'goldens/empty_hint_light.png',
      );
    }, skip: !Platform.isWindows);

    testWidgets('should match the stable dark golden', (tester) async {
      await _expectEmptyHintGolden(
        tester,
        brightness: Brightness.dark,
        goldenFile: 'goldens/empty_hint_dark.png',
      );
    }, skip: !Platform.isWindows);
  });
}

Future<void> _expectEmptyHintGolden(
  WidgetTester tester, {
  required Brightness brightness,
  required String goldenFile,
}) async {
  tester.view
    ..physicalSize = const Size(320, 180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = buildLanCloudTheme(
    brightness: brightness,
    seed: LanCloudApp.seed,
    oledDark: false,
  );
  const goldenKey = ValueKey<String>('empty-hint-golden');

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
        body: Center(
          child: RepaintBoundary(
            key: goldenKey,
            child: SizedBox(
              width: 320,
              height: 180,
              child: ColoredBox(
                color: theme.colorScheme.surface,
                child: const EmptyHint(
                  icon: Icons.folder_open,
                  text: '这个文件夹是空的',
                  animate: false,
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
