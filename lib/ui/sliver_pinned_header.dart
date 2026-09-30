import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 固定内容高度、钉在顶部的 sliver 头部。
///
/// 用于网盘页的路径栏：顶栏随内容滑走，它则钉住不动。当它顶到视口顶部
/// （顶栏已完全滑走）时，会把 [topInset]（状态栏高度）并入自身并绘制背景，
/// 替滑走的顶栏盖住状态栏区域；并入过程按“距视口顶部的距离”连续过渡，
/// 内容不会因此跳动。
class SliverPinnedHeader extends SingleChildRenderObjectWidget {
  const SliverPinnedHeader({
    super.key,
    required Widget super.child,
    required this.height,
    this.topInset = 0,
    this.tint = 0,
  });

  /// 内容本身的高度（路径栏高度）。
  final double height;

  /// 顶到视口顶部时并入自身的状态栏高度；为 0 则不并入。
  final double topInset;

  /// 顶栏滚动变色进度（0=顶部，1=已滚动），背景与顶栏保持同色。
  final double tint;

  @override
  RenderSliverPinnedHeader createRenderObject(BuildContext context) {
    return RenderSliverPinnedHeader(height, topInset, _backgroundColor(context));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverPinnedHeader renderObject,
  ) {
    renderObject
      ..height = height
      ..topInset = topInset
      ..backgroundColor = _backgroundColor(context);
  }

  Color _backgroundColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Color.lerp(scheme.surface, scheme.surfaceContainerHighest, tint) ??
        scheme.surface;
  }
}

class RenderSliverPinnedHeader extends RenderSliverSingleBoxAdapter {
  RenderSliverPinnedHeader(this._height, this._topInset, this._backgroundColor);

  double get height => _height;
  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  double get topInset => _topInset;
  double _topInset;
  set topInset(double value) {
    if (value == _topInset) return;
    _topInset = value;
    markNeedsLayout();
  }

  Color get backgroundColor => _backgroundColor;
  Color _backgroundColor;
  set backgroundColor(Color value) {
    if (value == _backgroundColor) return;
    _backgroundColor = value;
    if (_needsBackground) markNeedsPaint();
  }

  bool _needsBackground = false;
  double _inset = 0.0;

  @override
  void performLayout() {
    final SliverConstraints constraints = this.constraints;
    child!.layout(
      constraints.asBoxConstraints(minExtent: _height, maxExtent: _height),
      parentUsesSize: true,
    );
    final double childExtent = child!.size.height;

    // 距视口顶部的距离：顶栏尚未滑走时为正，顶到顶部后为 0。
    final double distanceToTop = clampDouble(
      constraints.viewportMainAxisExtent - constraints.remainingPaintExtent,
      0.0,
      double.infinity,
    );
    _inset = clampDouble(_topInset - distanceToTop, 0.0, _topInset);
    final bool isPinned =
        constraints.overlap > 0.0 || constraints.scrollOffset > 0.0;
    _needsBackground = isPinned || _inset > 0.0;

    final double totalExtent = childExtent + _inset;
    final double effectiveRemainingPaintExtent = math.max(
      0.0,
      constraints.remainingPaintExtent - constraints.overlap,
    );
    final double layoutExtent = clampDouble(
      totalExtent - constraints.scrollOffset,
      0.0,
      effectiveRemainingPaintExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: childExtent,
      paintOrigin: 0.0,
      paintExtent: math.min(totalExtent, effectiveRemainingPaintExtent),
      layoutExtent: layoutExtent,
      maxPaintExtent: totalExtent,
      maxScrollObstructionExtent: totalExtent,
      cacheExtent: layoutExtent > 0.0
          ? -constraints.cacheOrigin + layoutExtent
          : layoutExtent,
      hasVisualOverflow: false,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !geometry!.visible) return;
    if (_needsBackground) {
      context.canvas.drawRect(
        Rect.fromLTWH(
          offset.dx,
          offset.dy,
          constraints.crossAxisExtent,
          geometry!.paintExtent,
        ),
        Paint()..color = _backgroundColor,
      );
    }
    context.paintChild(child!, offset + Offset(0.0, _inset));
  }

  @override
  double childMainAxisPosition(RenderBox child) => _inset;

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    assert(child == this.child);
    applyPaintTransformForBoxChild(child as RenderBox, transform);
  }

  @override
  bool hitTestSelf({
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) => true;
}
