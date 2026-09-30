import 'package:flutter/material.dart';

/// 固定高度、始终钉在顶部的 sliver 头部。
/// 用于网盘页的路径栏：工具栏可以随内容滑走，但它始终可见。
class SliverPinnedHeader extends StatelessWidget {
  const SliverPinnedHeader({
    super.key,
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedHeaderDelegate(height: height, child: child),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

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
    return Material(
      color: overlapsContent
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.surface,
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  bool shouldRebuild(_PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
