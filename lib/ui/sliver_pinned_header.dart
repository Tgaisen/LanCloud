import 'package:flutter/material.dart';

/// 固定高度、始终钉在顶部的 sliver 头部。
/// 用于网盘页的路径栏：工具栏可以随内容滑走，但它始终可见。
class SliverPinnedHeader extends StatelessWidget {
  const SliverPinnedHeader({
    super.key,
    required this.height,
    required this.child,
    this.tint,
  });

  final double height;
  final Widget child;

  /// 顶栏滚动变色进度（0=顶部，1=已滚动）。非 null 时跟随顶栏一起变色，
  /// 否则回退为按 [overlapsContent] 二值切换。
  final double? tint;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedHeaderDelegate(height: height, child: child, tint: tint),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.height,
    required this.child,
    this.tint,
  });

  final double height;
  final Widget child;
  final double? tint;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tint = this.tint;
    return Material(
      color: tint == null
          ? (overlapsContent
              ? scheme.surfaceContainerHighest
              : scheme.surface)
          : (Color.lerp(
                  scheme.surface, scheme.surfaceContainerHighest, tint) ??
              scheme.surface),
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  bool shouldRebuild(_PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.child != child ||
      oldDelegate.tint != tint;
}
