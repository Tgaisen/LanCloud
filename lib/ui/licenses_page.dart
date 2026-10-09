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
class _PackageLicenses {
  _PackageLicenses(this.name, this.entries);

  final String name;
  final List<LicenseEntry> entries;
}

class _LicensesPageState extends State<LicensesPage> {
  final ScrollController _scroll = ScrollController();
  late final Future<List<_PackageLicenses>> _packages = _collect();

  /// 按包名聚合 [LicenseRegistry] 里的许可证，包名按字母序排列。
  static Future<List<_PackageLicenses>> _collect() async {
    final byPackage = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final name in entry.packages) {
        byPackage.putIfAbsent(name, () => <LicenseEntry>[]).add(entry);
      }
    }
    final names = byPackage.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final name in names) _PackageLicenses(name, byPackage[name]!)];
  }

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
        title: Text(context.l10n.aboutLicenses),
      ),
      slivers: [
        FutureBuilder<List<_PackageLicenses>>(
          future: _packages,
          builder: (context, snapshot) {
            final packages = snapshot.data;
            if (packages == null) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: M3eLoadingIndicator()),
              );
            }
            final detailText = MaterialLocalizations.of(context)
                .licensesPackageDetailText;
            // 与「关于」「传输」等页面同款 MD3E 连接式列表组：
            // 外层 12 + 分组自身 4 = 16dp 视觉内边距，条目之间是空白而非分割线
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              sliver: SegmentedSliverList(
                itemCount: packages.length,
                itemBuilder: (context, index) {
                  final package = packages[index];
                  return ListTile(
                    title: Text(package.name),
                    subtitle: Text(detailText(package.entries.length)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _PackageLicensePage(package: package),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        // 列表底部让开系统手势区（与其它页面一致）
        SliverToBoxAdapter(
          child: SizedBox(height: shellBottomBarInset(context)),
        ),
      ],
    );
  }
}

/// 单个依赖包的许可证正文。段落格式沿用 Flutter 自带实现：
/// `indent == LicenseParagraph.centeredIndent` 的段落居中加粗，其余按缩进排。
class _PackageLicensePage extends StatefulWidget {
  const _PackageLicensePage({required this.package});

  final _PackageLicenses package;

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TopBarOverlayScaffold(
      controller: _scroll,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const AppBarBackButton(),
        title: Text(widget.package.name),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          // 整块布局：一个包里可能有好几条许可，且正文长短差得很大；
          // 懒布局会按「已构建条目的平均高度」估算 maxScrollExtent，
          // 滑动时不断被修正 -> 滚动条滑块长度抖动（与设置页同款问题，见 SliverColumn）
          sliver: SliverColumn(
            children: [
              for (final entry in widget.package.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
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
                            if (paragraph.indent ==
                                LicenseParagraph.centeredIndent)
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
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: shellBottomBarInset(context)),
        ),
      ],
    );
  }
}
