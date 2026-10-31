import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用启动与运行时平台信号。
///
/// 这些字段不归属账号、目录或某个设置分组，但外壳需要在状态变化时局部刷新，
/// 因此由 [AppRuntimeState] 唯一持有；[AppController] 迁移期只做转发。
class AppRuntimeState {
  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<bool> secureStorageNeedsReauthentication =
      ValueNotifier(false);
  final ValueNotifier<bool> systemReduceMotion = ValueNotifier(false);

  void dispose() {
    ready.dispose();
    secureStorageNeedsReauthentication.dispose();
    systemReduceMotion.dispose();
  }
}

/// 应用级运行时状态；不使用 `autoDispose`。
final appRuntimeStateProvider = Provider<AppRuntimeState>((ref) {
  final state = AppRuntimeState();
  ref.onDispose(state.dispose);
  return state;
});
