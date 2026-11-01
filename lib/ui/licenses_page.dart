import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseParagraph, LicenseRegistry;
import 'package:material_ui/material_ui.dart' hide Icons;

import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'm3e.dart';

/// 开源许可页。
///
/// 用应用自己的顶栏样式（和设置 / 关于等页面一致），并且不像 Flutter 自带的
/// [LicensePage] 那样在顶部显示「应用名 + 版本 + powered by Flutter」页头，
/// 直接从依赖包列表开始。
class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key});

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

/// 同一个包名下的全部许可证条目。
class LicensePackageGroup {
  const LicensePackageGroup({required this.name, required this.entries});

  final String name;
  final List<LicenseEntry> entries;
}

class _LicensesPageState extends State<LicensesPage> {
  final ScrollController _scroll = ScrollController();

  List<LicensePackageGroup>? _packages;

  @override
  void initState() {
    super.initState();
    _loadLicenses().then((packages) {
      if (mounted) setState(() => _packages = packages);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packages = _packages;
    return TopBarOverlayScaffold(
      controller: _scroll,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(context.l10n.aboutLicenses),
      ),
      slivers: [
        if (packages == null)
          // 首次打开：指示器在内容区正中（与内嵌 WebView 的加载态一致）
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: M3eLoadingIndicator(semanticsLabel: context.l10n.loading),
            ),
          )
        else
          M3eReadingSliverPadding(
            padding: kM3eSectionPagePadding.copyWith(top: 16),
            // 懒构建：许可包数量多，一次性构建全部条目会让进入时卡一下；
            // 包条目的高度一致，SliverList 的滚动范围估算也是稳定的。
            sliver: SegmentedSliverList(
              itemCount: packages.length,
              itemBuilder: (context, index) =>
                  _packageTile(context, packages[index]),
            ),
          ),
      ],
    );
  }
}

/// 收集许可条目并缓存：再次进入许可页时直接复用，避免每次重新遍历
/// [LicenseRegistry]（注册发生在启动阶段，页面打开后再注册的情况不存在）。
Future<List<LicensePackageGroup>>? _licensesCache;

Future<List<LicensePackageGroup>> _loadLicenses() =>
    _licensesCache ??= _collectLicenses();

/// 按包名聚合 [LicenseRegistry] 里的许可证，包名按字母序排列。
Future<List<LicensePackageGroup>> _collectLicenses() async {
  final byPackage = <String, List<LicenseEntry>>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final name in entry.packages) {
      byPackage.putIfAbsent(name, () => <LicenseEntry>[]).add(entry);
    }
  }
  final names = byPackage.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final name in names)
      LicensePackageGroup(name: name, entries: byPackage[name]!),
  ];
}

/// 列表里的一个依赖包条目：点开看该包的许可正文。
Widget _packageTile(
  BuildContext context,
  LicensePackageGroup package, {
  ValueChanged<LicensePackageGroup>? onOpenPackage,
}) {
  final detailText = MaterialLocalizations.of(context)
      .licensesPackageDetailText;
  return ListTile(
    title: Text(package.name),
    subtitle: Text(detailText(package.entries.length)),
    trailing: const Icon(Icons.chevron_right),
    onTap: () {
      if (onOpenPackage != null) {
        onOpenPackage(package);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PackageLicensePage(package: package),
        ),
      );
    },
  );
}

/// 开源许可正文：依赖包列表（按包名聚合），点条目看该包的许可正文。
/// 独立页（push）与「我的」右窗格共用。
class LicensesContent extends StatefulWidget {
  const LicensesContent({super.key, this.onOpenPackage, this.loadingMinHeight});

  /// 大屏右窗格中由宿主接管详情导航；为空时 push 独立详情页。
  final ValueChanged<LicensePackageGroup>? onOpenPackage;

  /// 嵌入可滚动窗格时，加载态至少铺满正文可用高度以保持垂直居中。
  final double? loadingMinHeight;

  @override
  State<LicensesContent> createState() => _LicensesContentState();
}

class _LicensesContentState extends State<LicensesContent> {
  late final Future<List<LicensePackageGroup>> _packages = _loadLicenses();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LicensePackageGroup>>(
      future: _packages,
      builder: (context, snapshot) {
        final packages = snapshot.data;
        if (packages == null) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: widget.loadingMinHeight ?? 96,
            ),
            child: Center(
              child: M3eLoadingIndicator(semanticsLabel: context.l10n.loading),
            ),
          );
        }
        // 与设置类页面同款 MD3E 连接式列表组：
        // 外层 16 + 分组自身 4 = 20dp 视觉内边距，条目之间是空白而非分割线
        return SegmentedList(
          children: [
            for (final package in packages)
              _packageTile(
                context,
                package,
                onOpenPackage: widget.onOpenPackage,
              ),
          ],
        );
      },
    );
  }
}

/// 单个依赖包的许可证正文。段落格式沿用 Flutter 自带实现：
/// `indent == LicenseParagraph.centeredIndent` 的段落居中加粗，其余按缩进排。
class _PackageLicensePage extends StatefulWidget {
  const _PackageLicensePage({required this.package});

  final LicensePackageGroup package;

  @override
  State<_PackageLicensePage> createState() => _PackageLicensePageState();
}

class _PackageLicensePageState extends State<_PackageLicensePage> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TopBarOverlayScaffold(
      controller: _scroll,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(widget.package.name),
      ),
      slivers: [
        M3eReadingSliverPadding(
          padding: const EdgeInsets.all(16),
          // 整块布局：一个包里可能有好几条许可，且正文长短差得很大；
          // 懒布局会按「已构建条目的平均高度」估算 maxScrollExtent，
          // 滑动时不断被修正 -> 滚动条滑块长度抖动（与设置页同款问题，见 SliverColumn）
          sliver: SliverToBoxAdapter(
            child: LicenseDetailContent(package: widget.package),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: shellBottomBarInset(context)),
        ),
      ],
    );
  }
}

/// 单个依赖包的许可正文：独立页与「我的」右窗格共用。
class LicenseDetailContent extends StatelessWidget {
  const LicenseDetailContent({super.key, required this.package});

  final LicensePackageGroup package;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // 与许可首页 SegmentedList 的 4dp 组沿对齐，嵌套在页面 16dp 外边距内。
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, entry) in package.entries.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                key: ValueKey('license-detail-card-$index'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                // 许可证正文允许选中复制
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final paragraph in entry.paragraphs)
                        if (paragraph.indent == LicenseParagraph.centeredIndent)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              paragraph.text,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          Padding(
                            padding: EdgeInsetsDirectional.only(
                              top: 8,
                              start: 16.0 * paragraph.indent,
                            ),
                            child: Text(paragraph.text),
                          ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
