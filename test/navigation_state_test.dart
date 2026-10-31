import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_controller.dart';
import 'package:lancloud/core/navigation_state.dart';

void main() {
  test('NavigationState 管理多选、返回处理器和网盘返回能力', () {
    final state = NavigationState();
    addTearDown(state.dispose);
    var changes = 0;
    state.addListener(() => changes += 1);
    void exitSelection() {}
    Future<bool> driveBack() async => true;
    Future<bool> profileBack() async => true;
    int switched = -1;

    state.setSelectionMode(true);
    state.setSelectionMode(true);
    state.onRequestExitSelection = exitSelection;
    state.onDriveBack = driveBack;
    state.onProfileBack = profileBack;
    state.onSwitchTab = (index) => switched = index;
    state.switchTab(2);
    state.driveCanHandleBack.value = true;

    expect(state.selectionMode, isTrue);
    expect(changes, 1);
    expect(state.onRequestExitSelection, exitSelection);
    expect(state.onDriveBack, driveBack);
    expect(state.onProfileBack, profileBack);
    expect(switched, 2);
    expect(state.driveCanHandleBack.value, isTrue);
    expect(state.activeTab.value, 0);
  });

  test('AppController 旧 API 转发到同一 NavigationState', () {
    final navigation = NavigationState();
    final app = AppController(navigation: navigation);
    addTearDown(app.dispose);
    var notifications = 0;
    app.addListener(() => notifications += 1);

    expect(notifications, 0);
    expect(identical(app.barsHide, navigation.barsHide), isTrue);
    expect(identical(app.topBarHide, navigation.topBarHide), isTrue);
  });

  test('navigationStateProvider 可以被入口共享实例覆盖', () {
    final navigation = NavigationState();
    final container = ProviderContainer(
      overrides: [navigationStateProvider.overrideWithValue(navigation)],
    );
    addTearDown(container.dispose);
    addTearDown(navigation.dispose);

    expect(
      identical(container.read(navigationStateProvider), navigation),
      isTrue,
    );
  });
}
