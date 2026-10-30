import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用外壳与子页面共享的导航交互状态。
///
/// 本切片只承载多选、返回处理器和网盘返回能力；Tab、动画进度等仍留在
/// `AppController`，后续再逐项迁移。
class NavigationState extends ChangeNotifier {
  bool _selectionMode = false;

  VoidCallback? onRequestExitSelection;

  /// 网盘页注册的返回处理：返回 true 表示已消费（例如返回上一级目录）。
  Future<bool> Function()? onDriveBack;

  /// 「我的」页注册的返回处理：返回 true 表示已消费。
  Future<bool> Function()? onProfileBack;

  final ValueNotifier<bool> driveCanHandleBack = ValueNotifier<bool>(false);

  /// 顶栏/底栏滑动隐藏进度 0..1，由各页面按滚动距离驱动。
  final ValueNotifier<double> barsHide = ValueNotifier(0);

  /// 当前激活的 page 视图下标。
  final ValueNotifier<int> activeTab = ValueNotifier(0);

  /// 顶栏收起进度 0..1。
  final ValueNotifier<double> topBarHide = ValueNotifier(0);

  late final Ticker _barsTicker = Ticker(_onBarsTick);
  double _barsFrom = 0;
  double _barsTo = 0;
  double _topBarFrom = 0;
  Curve _barsCurve = Curves.easeOutCubic;
  Duration _barsDuration = const Duration(milliseconds: 240);

  bool get selectionMode => _selectionMode;

  void setSelectionMode(bool value) {
    if (_selectionMode == value) return;
    _selectionMode = value;
    notifyListeners();
  }

  /// 滚动驱动：1:1 跟随手指，立即生效并打断正在播放的程序化动画。
  void setBarsHideFromScroll(double value) {
    if (_barsTicker.isActive) _barsTicker.stop();
    final target = value.clamp(0.0, 1.0);
    if (barsHide.value != target) barsHide.value = target;
  }

  /// 顶栏滚动驱动：1:1 跟随手指。
  void setTopBarHideFromScroll(double value) {
    if (_barsTicker.isActive) _barsTicker.stop();
    final target = value.clamp(0.0, 1.0);
    if (topBarHide.value != target) topBarHide.value = target;
  }

  /// 程序化显示/隐藏顶栏与底栏。
  void animateBarsHide(
    double target, {
    required bool reduceMotion,
    Duration duration = const Duration(milliseconds: 240),
    Curve curve = Curves.easeOutCubic,
  }) {
    final to = target.clamp(0.0, 1.0);
    if (reduceMotion) {
      _barsTicker.stop();
      if (barsHide.value != to) barsHide.value = to;
      if (topBarHide.value != to) topBarHide.value = to;
      return;
    }
    if (to == barsHide.value && to == topBarHide.value) return;
    _barsFrom = barsHide.value;
    _topBarFrom = topBarHide.value;
    _barsTo = to;
    _barsCurve = curve;
    _barsDuration = duration;
    _barsTicker
      ..stop()
      ..start();
  }

  void _onBarsTick(Duration elapsed) {
    final total = _barsDuration.inMicroseconds;
    final t = total <= 0
        ? 1.0
        : (elapsed.inMicroseconds / total).clamp(0.0, 1.0);
    barsHide.value =
        (_barsFrom + (_barsTo - _barsFrom) * _barsCurve.transform(t)).clamp(
          0.0,
          1.0,
        );
    topBarHide.value =
        (_topBarFrom + (_barsTo - _topBarFrom) * _barsCurve.transform(t)).clamp(
          0.0,
          1.0,
        );
    if (t >= 1) _barsTicker.stop();
  }

  @override
  void dispose() {
    _barsTicker.dispose();
    barsHide.dispose();
    topBarHide.dispose();
    activeTab.dispose();
    super.dispose();
  }
}

/// 应用级导航状态；阶段 3 过渡期由 `AppController` 转发通知。
final navigationStateProvider = Provider<NavigationState>((ref) {
  throw StateError('navigationStateProvider 必须由应用入口覆盖');
});
