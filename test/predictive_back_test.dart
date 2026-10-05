import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/app.dart';

void main() {
  group('预测性返回：返回手势交给系统的条件', () {
    bool canPop({
      bool selectionMode = false,
      bool hasActiveTransfers = false,
      bool atDefaultView = true,
      bool driveCanHandleBack = false,
    }) => canHandBackToSystem(
      selectionMode: selectionMode,
      hasActiveTransfers: hasActiveTransfers,
      atDefaultView: atDefaultView,
      driveCanHandleBack: driveCanHandleBack,
    );

    test('默认视图且没有要拦截的目标：交给系统（播放退回桌面动画）', () {
      expect(canPop(), isTrue);
    });

    test('多选（网盘 / 传输 / 收藏共用 selectionMode）：自己处理，先退出多选', () {
      expect(canPop(selectionMode: true), isFalse);
    });

    test('有进行中的传输：自己处理，先弹退出确认', () {
      expect(canPop(hasActiveTransfers: true), isFalse);
    });

    test('不在默认视图：自己处理，先切回默认视图', () {
      expect(canPop(atDefaultView: false), isFalse);
    });

    test('网盘页在子目录 / 搜索中：自己处理，先返回上一级', () {
      expect(canPop(driveCanHandleBack: true), isFalse);
    });
  });
}
