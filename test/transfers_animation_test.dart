import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/navigation_appearance_settings_state.dart';
import 'package:lancloud/core/navigation_state.dart';
import 'package:lancloud/core/system_motion.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/core/transfer/transfer_manager_provider.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/transfers_page.dart';

import 'package:lancloud/l10n/delegates.dart';

import 'transfer_dependencies_test.dart' show buildTransferManagerForEnvironment;

void main() {
  setUp(() {
    // 全局动效状态在测试之间复位（否则「移除动画」会让入场动画直接到位）
    SystemMotion.motionMode.value = 'auto';
    SystemMotion.reduceMotion.value = false;
    SystemMotion.touchExploration.value = false;
  });

  testWidgets('切走再切回传输页：列表不重播入场动画', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final manager = buildTransferManagerForEnvironment(environment);
    manager.tasks.add(
      TransferTask(
        id: 't1',
        kind: TransferKind.upload,
        name: 'a.zip',
        accountUid: '',
        localFilePath: '/tmp/a.zip',
      )..status = TransferStatus.done,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferManagerProvider.overrideWithValue(manager),
          navigationAppearanceSettingsStateProvider.overrideWithValue(
            environment.navigationAppearanceSettings,
          ),
          navigationStateProvider.overrideWithValue(environment.navigation),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const TransfersPage(),
        ),
      ),
    );
    // 首次加载：整组入场动画播一遍（initState 的 post-frame 回调起步）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 条目上层的所有 Opacity（含列表的共享入场进度）都应该是 1
    Iterable<double> itemOpacities(String name) {
      return tester
          .widgetList<Opacity>(
            find.ancestor(of: find.text(name), matching: find.byType(Opacity)),
          )
          .map((o) => o.opacity);
    }

    void expectFullyVisible(String name) {
      expect(
        itemOpacities(name).every((o) => o == 1),
        isTrue,
        reason: '条目 $name 不应在切回后重新淡入',
      );
    }

    expectFullyVisible('a.zip');

    // 切到别的视图（外壳更新 activeTab），再切回传输视图：
    // 之前这里会给整组列表重播一次入场动画，与首页 / 收藏等页面不一致
    environment.navigation.activeTab.value = 0;
    await tester.pump();
    environment.navigation.activeTab.value = 2;
    await tester.pump(const Duration(milliseconds: 60));
    expectFullyVisible('a.zip');
  });
}
