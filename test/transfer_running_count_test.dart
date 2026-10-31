import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_environment.dart';
import 'package:lancloud/core/transfer/transfer_manager.dart';
import 'package:lancloud/ui/transfer_running_count.dart';
import 'package:material_ui/material_ui.dart';

import 'transfer_dependencies_test.dart'
    show buildTransferManagerForEnvironment;

void main() {
  testWidgets('仅运行中任务数变化时重建', (tester) async {
    final environment = AppEnvironment();
    addTearDown(environment.dispose);
    final manager = buildTransferManagerForEnvironment(environment);
    addTearDown(manager.dispose);
    manager.tasks.add(
      TransferTask(
        id: 't1',
        kind: TransferKind.upload,
        name: 'a.zip',
        accountUid: '',
      )..status = TransferStatus.running,
    );
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: TransferRunningCount(
          manager: manager,
          builder: (context, running) {
            builds += 1;
            return Text('$running');
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    final initialBuilds = builds;

    // 取消后任务数 1 → 0，需要重建。
    manager.cancel('t1');
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    expect(builds, initialBuilds + 1);

    // 已取消任务再次取消仍会 notifyListeners，但任务数没变，不应重建。
    manager.cancel('t1');
    await tester.pump();
    expect(builds, initialBuilds + 1);
  });
}
