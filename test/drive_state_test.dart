import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/drive_state.dart';

void main() {
  test('DriveState 管理目录请求、位置和可见性探针', () {
    final state = DriveState();
    addTearDown(state.dispose);
    var driveVisible = true;
    var favoritesVisible = false;
    bool failingProbe() => throw StateError('hidden');

    state.folderRequest.value = 'folder-1';
    state.location.value = const DriveLocation(id: 'folder-1', path: 'A/B');
    state.addDriveProbe(() => driveVisible);
    state.addDriveProbe(failingProbe);
    state.addFavoritesProbe(() => favoritesVisible);

    expect(state.folderRequest.value, 'folder-1');
    expect(state.location.value.path, 'A/B');
    expect(identical(state.cache, state.cache), isTrue);
    expect(state.driveVisible, isTrue);
    expect(state.favoritesVisible, isFalse);

    driveVisible = false;
    favoritesVisible = true;
    expect(state.driveVisible, isFalse);
    expect(state.favoritesVisible, isTrue);
  });

  test('driveStateProvider 可以被入口共享实例覆盖', () {
    final drive = DriveState();
    final container = ProviderContainer(
      overrides: [driveStateProvider.overrideWithValue(drive)],
    );
    addTearDown(container.dispose);
    addTearDown(drive.dispose);

    expect(identical(container.read(driveStateProvider), drive), isTrue);
    expect(identical(container.read(driveCacheProvider), drive.cache), isTrue);
  });
}
