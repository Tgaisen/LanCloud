import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:provider/provider.dart';

import '../core/api/lanzou_client.dart';
import '../core/api/models.dart';
import '../core/app_controller.dart';
import '../core/transfer/transfer_manager.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'common.dart';
import 'download_mark.dart';
import 'm3e.dart';

/// 分享文件属性弹窗：加载时显示小圆环，加载完展示简介与文件信息，
/// 提供下载、复制链接、二维码与收藏（「打开链接」已按需求去掉）。
class ShareFileInfoSheet extends StatefulWidget {
  const ShareFileInfoSheet({
    super.key,
    required this.name,
    required this.url,
    required this.pwd,
    this.size = '',
    this.time = '',
    this.invalid = false,
  });

  final String name;
  final String url;
  final String pwd;
  final String size;
  final String time;

  /// 已知失效的条目（服务端 id 为 -1）：不再去解析链接，直接提示「文件已失效」。
  final bool invalid;

  @override
  State<ShareFileInfoSheet> createState() => _ShareFileInfoSheetState();
}

class _ShareFileInfoSheetState extends State<ShareFileInfoSheet> {
  bool _loading = true;
  bool _invalid = false;
  DirectFile? _resolved;

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
      pwd: widget.pwd,
      fallbackName: _name,
      showLoading: false,
    );
    if (mounted) setState(() => _resolvingDownload = false);
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
    final client = context.read<AppController>().publicClient;
    try {
      final resolved = await client.resolveFileShare(
        widget.url,
        pwd: widget.pwd,
      );
      if (mounted) setState(() => _resolved = resolved);
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

  String get _name {
    final resolved = _resolved;
    if (resolved != null && resolved.name.isNotEmpty) return resolved.name;
    return widget.name;
  }

  String get _size {
    final resolved = _resolved;
    if (resolved != null && resolved.size.isNotEmpty) return resolved.size;
    return widget.size;
  }

  String get _desc => _resolved?.desc ?? '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final navigator = Navigator.of(context);
    final transfers = context.read<TransferManager>();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PropertyHeaderCard(
            icon: iconForFile(_name),
            iconColor: fileIconColor(_name, brightness: scheme.brightness),
            title: _name,
            subtitle: [
              if (_size.isNotEmpty) prettyLzSize(_size),
              if (widget.time.isNotEmpty) widget.time,
            ].join(' · '),
            desc: _desc,
            loading: _loading,
          ),
          if (_invalid)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              // 已知失效 / 链接解析失败：Error container 卡片提示
              child: ErrorHintCard(
                message: widget.invalid ? l10n.fileInvalid : l10n.shareInvalid,
              ),
            ),
          // 下载状态原位显示：解析中 / 等待中 / 下载中在行尾显示进度环，
          // 已下载 / 下载失败换图标与文案；已加入下载后点击弹二级菜单
          // （打开 / 分享 / 取消下载 / 重新下载）
          ListenableBuilder(
            // 进度更新走 manager（环要动）；标记集合变化走低频 revision，
            // 两者都听，状态切换不会漏刷新
            listenable: Listenable.merge([transfers, transfers.marksRevision]),
            builder: (BuildContext context, _) {
              final mark = transfers.downloadMarkOf(widget.url);
              final status = mark?.status;
              final resolving = _resolvingDownload;
              final active =
                  resolving ||
                  status == TransferStatus.queued ||
                  status == TransferStatus.running;
              final title = resolving
                  ? l10n.resolving
                  : switch (status) {
                      TransferStatus.queued => l10n.waitingToDownload,
                      TransferStatus.running => l10n.downloading,
                      TransferStatus.done => l10n.downloaded,
                      TransferStatus.failed => l10n.downloadFailed,
                      _ => l10n.download,
                    };
              return Builder(
                builder: (BuildContext rowContext) => ListTile(
                  enabled: !_invalid,
                  leading: Icon(switch (status) {
                    TransferStatus.done => Icons.download_done,
                    TransferStatus.failed => Icons.file_download_off,
                    _ => Icons.download_outlined,
                  }),
                  title: Text(title),
                  trailing: !active
                      ? null
                      : M3eCircularProgressIndicator(
                          // 下载中显示确定进度；解析中 / 排队中 / 大小未知
                          // 都是不确定态
                          value:
                              status == TransferStatus.running &&
                                  (mark?.total ?? 0) > 0
                              ? mark?.progress
                              : null,
                          size: 24,
                          strokeWidth: 2.5,
                        ),
                  onTap: () {
                    if (mark != null) {
                      final anchor = m3eMenuAnchorOf(rowContext);
                      if (anchor == null) return;
                      showDownloadTaskMenu(
                        context,
                        anchor: anchor,
                        task: mark,
                        // 重新下载：旧任务已删，重新解析直链；解析期间同样
                        // 走「解析中」状态（行尾不确定态环）
                        onRedownload: _startDownload,
                      );
                      return;
                    }
                    // 解析中忽略再次点击；解析失败会回到「下载」原状
                    _startDownload();
                  },
                ),
              );
            },
          ),
          ListTile(
            enabled: !_invalid,
            leading: const Icon(Icons.copy),
            title: Text(l10n.copyLink),
            onTap: () {
              navigator.pop();
              copyText(context, widget.url);
            },
          ),
          ListTile(
            enabled: !_invalid,
            leading: const Icon(Icons.qr_code),
            title: Text(l10n.showQr),
            onTap: () {
              navigator.pop();
              showQrDialog(
                // 用 navigator 的 context：弹窗刚被 pop，原 context 已失效
                navigator.context,
                title: _name,
                url: widget.url,
                pwd: widget.pwd,
              );
            },
          ),
          ListTile(
            // 收藏态查出来之前先置灰：否则会在状态未知时点出重复收藏 / 错误取消
            enabled: !_invalid && _favorite != null,
            leading: Icon(
              Icons.star_outline,
              // 已收藏切到实心星（FILL 轴），未收藏保持描边
              fill: _favorite == true ? 1 : 0,
            ),
            title: Text(_favorite == true ? l10n.unfavorite : l10n.favorite),
            onTap: () async {
              // 与网盘页属性弹窗一致：收藏就地切换，不关弹窗（反馈走轻提示）
              final next = await toggleFavoriteByRef(
                context,
                kind: 'shareFile',
                name: _name,
                ref: widget.url,
                pwd: widget.pwd,
                size: _size,
                sharer: _resolved?.sharer ?? '',
              );
              if (next != null && mounted) {
                setState(() => _favorite = next);
              }
            },
          ),
        ],
      ),
    );
  }
}
