import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/lanzou_client_registry.dart';
import '../core/api/models.dart';
import '../core/transfer/transfer_manager.dart';
import '../core/transfer/transfer_manager_provider.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'download_mark.dart';
import 'm3e.dart';
import 'share_password_dialog.dart';

/// 分享文件属性弹窗：加载时显示小圆环，加载完展示简介与文件信息，
/// 提供下载、复制链接、二维码与收藏（「打开链接」已按需求去掉）。
class ShareFileInfoSheet extends ConsumerStatefulWidget {
  const ShareFileInfoSheet({
    super.key,
    required this.name,
    required this.url,
    required this.pwd,
    this.size = '',
    this.time = '',
    this.sharer = '',
    this.invalid = false,
    this.onPasswordUpdated,
    this.onResolved,
  });

  final String name;
  final String url;
  final String pwd;
  final String size;
  final String time;

  /// 打开时已知的分享者（分享文件夹 / 收藏带过来）；解析出文件页的值后覆盖。
  final String sharer;

  /// 已知失效的条目（服务端 id 为 -1）：不再去解析链接，直接提示「文件已失效」。
  final bool invalid;

  /// 提取码验证通过后回调：收藏夹用它把新密码写回收藏数据。
  final Future<void> Function(String pwd)? onPasswordUpdated;

  /// 解析成功后回调：收藏夹用它把最新的名称 / 分享者写回收藏数据。
  final Future<void> Function(DirectFile file)? onResolved;

  @override
  ConsumerState<ShareFileInfoSheet> createState() => _ShareFileInfoSheetState();
}

enum _ShareFileQuickAction { download, copyLink, qr, favorite }

class _ShareFileInfoSheetState extends ConsumerState<ShareFileInfoSheet> {
  bool _loading = true;
  bool _invalid = false;
  DirectFile? _resolved;

  /// 下载按钮的二级菜单贴着该按钮组弹出。
  final GlobalKey _quickActionGroupKey = GlobalKey();

  /// 复制链接 / 二维码二选一菜单当前由哪个按钮触发。
  _ShareFileQuickAction? _linkMenuTarget;

  /// 当前使用的提取码：解析出「提取码错误」并重新验证后换成新的。
  late String _pwd = widget.pwd;

  /// 收藏状态：null = 还没查出来（查完之前收藏项置灰，避免点出「重复收藏」）。
  bool? _favorite;

  /// 正在解析直链（点了下载、任务还没入队）：行尾显示不确定态小环，
  /// 解析失败恢复「下载」原状。
  bool _resolvingDownload = false;

  /// 点「下载 / 重新下载」：解析期间先在行尾显示不确定态小环；失败恢复原状。
  Future<void> _startDownload() async {
    if (_resolvingDownload) return;
    setState(() => _resolvingDownload = true);
    await downloadShareFile(
      context,
      url: widget.url,
      pwd: _pwd,
      fallbackName: _name,
      showLoading: false,
      // 提取码错误（例如上传者改过）：先补密码，验证通过再继续入队
      askPassword: _promptPassword,
    );
    if (mounted) setState(() => _resolvingDownload = false);
  }

  TransferTask? get _downloadTask =>
      ref.read(transferManagerProvider).downloadMarkOf(widget.url);

  void _runQuickAction(_ShareFileQuickAction action) {
    if (_invalid) return;
    switch (action) {
      case _ShareFileQuickAction.download:
        final mark = _downloadTask;
        if (mark != null) {
          _openDownloadMenu(mark);
        } else if (!_resolvingDownload) {
          _startDownload();
        }
      case _ShareFileQuickAction.copyLink:
        _openLinkMenu(action);
      case _ShareFileQuickAction.qr:
        _openLinkMenu(action);
      case _ShareFileQuickAction.favorite:
        // 开关型按钮走 onToggled，这里不会命中。
        break;
    }
  }

  Future<void> _openDownloadMenu(TransferTask task) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final RenderBox? group =
        _quickActionGroupKey.currentContext?.findRenderObject() as RenderBox?;
    if (group == null || !group.hasSize) return;
    await showDownloadTaskMenu(
      context,
      anchor: _quickActionAnchor(group, 0),
      task: task,
      onRedownload: _startDownload,
    );
  }

  Future<void> _openLinkMenu(_ShareFileQuickAction target) async {
    if (_linkMenuTarget != target) {
      setState(() => _linkMenuTarget = target);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final RenderBox? group =
        _quickActionGroupKey.currentContext?.findRenderObject() as RenderBox?;
    if (group == null || !group.hasSize) return;
    final l10n = context.l10n;
    final qr = target == _ShareFileQuickAction.qr;
    final bool? direct = await showAdaptiveM3eMenu<bool>(
      context: context,
      anchor: _quickActionAnchor(
        group,
        target == _ShareFileQuickAction.qr ? 2 : 1,
      ),
      // 属性页本身已经是底部面板，二级菜单保持锚定菜单，避免面板叠面板。
      allowSheet: false,
      items: [
        M3eMenuItem(
          value: false,
          label: qr ? l10n.shareLinkQr : l10n.copyShareLink,
          icon: Icons.share_outlined,
        ),
        M3eMenuItem(
          value: true,
          label: qr ? l10n.directLinkQr : l10n.copyDirectLink,
          icon: Icons.file_present,
        ),
      ],
    );
    if (direct == null || !mounted) return;
    if (target == _ShareFileQuickAction.qr) {
      if (direct) {
        await _showDirectLinkQr();
      } else {
        await _showShareLinkQr();
      }
    } else if (direct) {
      await _copyDirectLink();
    } else {
      await _copyShareLink();
    }
  }

  Future<void> _copyShareLink() async {
    final l10n = context.l10n;
    await copyText(
      context,
      _pwd.isEmpty ? widget.url : l10n.linkWithPassword(widget.url, _pwd),
      asToast: true,
    );
  }

  Future<void> _copyDirectLink() async {
    final resolved = await _resolveDirectFile();
    if (!mounted || resolved == null) return;
    await copyText(context, resolved.url, asToast: true);
  }

  Future<void> _showShareLinkQr() =>
      showQrDialog(context, title: _name, url: widget.url, pwd: _pwd);

  Future<void> _showDirectLinkQr() async {
    final resolved = await _resolveDirectFile();
    if (!mounted || resolved == null) return;
    await showQrDialog(context, title: _name, url: resolved.url);
  }

  Future<DirectFile?> _resolveDirectFile() async {
    final cached = _resolved;
    if (cached != null && cached.url.isNotEmpty) return cached;
    final client = ref.read(lanzouClientRegistryProvider).publicClient;
    final navigator = Navigator.of(context);
    showLoadingDialog(context, context.l10n.resolving);
    DirectFile? resolved;
    Object? error;
    var needsPassword = false;
    try {
      resolved = await client.resolveFileShare(
        widget.url,
        pwd: _pwd,
        withDescription: true,
      );
    } on NeedPasswordException {
      needsPassword = true;
    } on WrongPasswordException {
      needsPassword = true;
    } catch (e) {
      error = e;
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
    if (!mounted) return null;
    if (needsPassword) {
      final pwd = await _promptPassword();
      return pwd == null ? null : _resolved;
    }
    if (error != null) {
      showAppToast(context, context.l10n.lanzouError(error));
      return null;
    }
    if (resolved != null) {
      setState(() => _resolved = resolved);
      await widget.onResolved?.call(resolved);
    }
    return resolved;
  }

  Future<void> _toggleFavorite(bool checked) async {
    setState(() => _favorite = checked);
    final next = await toggleFavoriteByRef(
      context,
      kind: 'shareFile',
      name: _name,
      ref: widget.url,
      pwd: _pwd,
      size: _size,
      sharer: _sharer,
    );
    if (!mounted) return;
    setState(() => _favorite = next ?? !checked);
  }

  @override
  void initState() {
    super.initState();
    // 已知失效的文件不必再发请求：链接解析一定失败，只会白转一圈
    if (widget.invalid) {
      _loading = false;
      _invalid = true;
    } else {
      _fetch();
    }
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final favorited = await isFavoritedByRef(context, widget.url);
    if (mounted) setState(() => _favorite = favorited);
  }

  Future<void> _fetch() async {
    final client = ref.read(lanzouClientRegistryProvider).publicClient;
    try {
      // 属性弹窗要显示简介：分享页没有时再去下载页（/tp）兜底
      final resolved = await client.resolveFileShare(
        widget.url,
        pwd: _pwd,
        withDescription: true,
      );
      if (mounted) setState(() => _resolved = resolved);
      await widget.onResolved?.call(resolved);
    } on NeedPasswordException {
      if (!mounted) return;
      setState(() => _loading = false);
      await _promptPassword();
    } on WrongPasswordException {
      if (!mounted) return;
      setState(() => _loading = false);
      await _promptPassword();
    } on LanzouException catch (e) {
      if (mounted) {
        setState(
          () =>
              _invalid = e.message.contains('不存在') || e.message.contains('取消'),
        );
      }
    } catch (_) {
      // 网络异常不视为失效，下载时会有明确提示。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 提取码缺失 / 错误：弹「此文件需要密码」，验证通过后用新密码刷新信息，
  /// 并通知外面（收藏夹）同步新密码。
  Future<String?> _promptPassword() async {
    final result = await showFilePasswordDialog(context, url: widget.url);
    if (result == null || !mounted) return null;
    setState(() {
      _pwd = result.pwd;
      _resolved = result.value;
      _invalid = false;
      _loading = false;
    });
    await widget.onResolved?.call(result.value);
    await widget.onPasswordUpdated?.call(result.pwd);
    return result.pwd;
  }

  String get _name {
    final resolved = _resolved;
    if (resolved != null && resolved.name.isNotEmpty) return resolved.name;
    return widget.name;
  }

  String get _size {
    // 分享文件夹列表里的 size 来自文件夹接口，和列表显示的一致；
    // 文件页解析出的 size 偶尔会取到别的数字（历史上是页内日期 22），
    // 有列表值时以列表为准，保证打开属性弹窗前后的显示不跳变。
    if (widget.size.isNotEmpty) return widget.size;
    final resolved = _resolved;
    return resolved?.size ?? '';
  }

  String get _desc => _resolved?.desc ?? '';

  String get _sharer {
    final resolved = _resolved;
    if (resolved != null && resolved.sharer.isNotEmpty) return resolved.sharer;
    return widget.sharer;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final transfers = ref.read(transferManagerProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PropertyHeaderCard(
            icon: iconForFile(_name),
            iconColor: fileIconColor(_name, brightness: scheme.brightness),
            title: _name,
            desc: _desc,
            loading: _loading,
          ),
          if (_invalid)
            // 已知失效 / 链接解析失败：与下方列表组使用同一左右边距。
            ErrorHintCard(
              message: widget.invalid ? l10n.fileInvalid : l10n.shareInvalid,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            ),
          // 下载 / 复制链接 / 二维码 / 收藏：与网盘文件属性页使用同一套按钮组。
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: KeyedSubtree(
              key: _quickActionGroupKey,
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  transfers,
                  transfers.marksRevision,
                ]),
                builder: (BuildContext context, _) {
                  final mark = transfers.downloadMarkOf(widget.url);
                  final resolving = _resolvingDownload;
                  final tooltip = resolving
                      ? l10n.resolving
                      : switch (mark?.status) {
                          TransferStatus.queued => l10n.waitingToDownload,
                          TransferStatus.resolving => l10n.resolving,
                          TransferStatus.running => l10n.downloading,
                          TransferStatus.resuming => l10n.resumingDownload,
                          TransferStatus.paused => l10n.paused,
                          TransferStatus.saving => l10n.saving,
                          TransferStatus.done => l10n.downloaded,
                          TransferStatus.failed => l10n.downloadFailed,
                          _ => l10n.download,
                        };
                  M3eCircularProgressIndicator ring({
                    required Color color,
                    double? value,
                  }) => M3eCircularProgressIndicator(
                    value: value,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.2),
                    size: 24,
                    strokeWidth: 2.5,
                  );
                  return M3EIconButtonGroup<_ShareFileQuickAction>(
                    items: [
                      M3EIconAction(
                        value: _ShareFileQuickAction.download,
                        icon: Icons.download_outlined,
                        checkedIcon: Icons.download_done,
                        tooltip: tooltip,
                        checked: mark != null,
                        enabled: !_invalid,
                        iconWidget: !resolving
                            ? null
                            : ring(color: scheme.onSecondaryContainer),
                        checkedIconWidget: switch (mark?.status) {
                          TransferStatus.queued => ring(
                            color: scheme.onSecondary,
                          ),
                          TransferStatus.resolving => ring(
                            color: scheme.onSecondary,
                          ),
                          TransferStatus.running => ring(
                            color: scheme.onSecondary,
                            value: (mark?.total ?? 0) > 0
                                ? mark?.progress
                                : null,
                          ),
                          TransferStatus.resuming => ring(
                            color: scheme.onSecondary,
                          ),
                          TransferStatus.paused => ring(
                            color: scheme.onSecondary,
                            value: (mark?.total ?? 0) > 0
                                ? mark?.progress
                                : null,
                          ),
                          TransferStatus.saving => ring(
                            color: scheme.onSecondary,
                            value: (mark?.total ?? 0) > 0
                                ? mark?.progress
                                : null,
                          ),
                          TransferStatus.failed => const Icon(
                            Icons.file_download_off,
                          ),
                          _ => null,
                        },
                      ),
                      M3EIconAction(
                        value: _ShareFileQuickAction.copyLink,
                        icon: Icons.link_outlined,
                        checkedIcon: Icons.link,
                        tooltip: l10n.copyLink,
                        enabled: !_invalid,
                      ),
                      M3EIconAction(
                        value: _ShareFileQuickAction.qr,
                        icon: Icons.qr_code,
                        checkedIcon: Icons.qr_code,
                        tooltip: l10n.showQr,
                        enabled: !_invalid,
                      ),
                      M3EIconAction(
                        value: _ShareFileQuickAction.favorite,
                        icon: Icons.star_border,
                        checkedIcon: Icons.star_outline,
                        tooltip: _favorite == true
                            ? l10n.unfavorite
                            : l10n.favorite,
                        checked: _favorite == true,
                        isToggle: true,
                        enabled: !_invalid && _favorite != null,
                      ),
                    ],
                    onPressed: _runQuickAction,
                    onToggled: (action, checked) {
                      if (action == _ShareFileQuickAction.favorite) {
                        _toggleFavorite(checked);
                      }
                    },
                  );
                },
              ),
            ),
          ),
          SheetListGroup(
            margin: SheetListGroup.endMargin,
            children: [
              PropertyDetailRow(
                label: l10n.propertyType,
                value: propertyFileTypeLabel(_name, l10n),
              ),
              PropertyDetailRow(
                label: l10n.propertySize,
                value: _size.isEmpty ? l10n.unknownSize : prettyLzSize(_size),
              ),
              PropertyDetailRow(
                label: l10n.propertyTime,
                value: widget.time.isEmpty ? '—' : widget.time,
              ),
              PropertyDetailRow(
                label: l10n.propertySharer,
                value: _sharer.isEmpty ? '—' : _sharer,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 分享文件属性页 4 个快捷按钮中，第 [index] 个按钮的全局矩形。
Rect _quickActionAnchor(RenderBox group, int index) {
  final double segment = m3eIconButtonWidth(group.size.width, 4);
  final Offset origin = group.localToGlobal(Offset.zero);
  return Rect.fromLTWH(
    origin.dx + index * (segment + kM3EIconButtonSpacing),
    origin.dy,
    segment,
    group.size.height,
  );
}
