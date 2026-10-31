import 'package:material_ui/material_ui.dart';

import 'm3e.dart';

/// MD3E 设置项滑杆：图标 + 标题 + 尾部当前值，下面一行滑杆。
///
/// **参考 M3 规范**：[M3ESlider]（XS 档：16dp 轨道 / 44dp 手柄、手柄按下变窄）
/// 采用 stops 配置——[values] 就是全部可取值，手柄吸附到最近的档；
/// 数值显示在行的 trailing text 位（「值显示在别处时不必再用浮动值标记」）。
/// 标题与值单独成行，滑杆放在下方独立一行，避免 ListTile 为 trailing 预留的
/// 宽度同时挤压 subtitle；滑杆轨道横跨标题左缘到当前值右缘。
///
/// **本应用的设计决定（非 M3 规范）**：拖动时只更新本地显示，松手才写设置
/// （避免拖动过程中反复落盘）。
///
/// **无障碍**：M3ESlider 是纯自绘控件、自身不产出滑杆语义，TalkBack 既读不出
/// 当前值也无法调节；这里在外面合成滑杆语义节点（slider 角色 + 当前值 +
/// 上/下调动作），并屏蔽内部手势语义（否则读屏双击会按成控件中心点按）。
///
/// **旧版读屏兼容性**：6.1 一脉的旧 TalkBack（如 Android 12 时代的版本、部分
/// 系统内置读屏）调整后只播报「进度条」：旧逻辑的数值取自调整事件里的
/// itemCount/currentItemIndex（原生 SeekBar 会填这两个字段，Flutter 引擎不发，
/// 应用层无法补齐）；新版 TalkBack 走节点文本，值照常播报。不要加
/// SemanticsService.announce / liveRegion 之类补偿——会让新版重复播报。
class SettingsSliderTile<T> extends StatefulWidget {
  const SettingsSliderTile({
    super.key,
    required this.icon,
    required this.title,
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;

  /// 可选的说明文字（滑杆上方的一行小字）。
  final String? subtitle;

  /// 全部可取值（顺序即滑杆从左到右的档位）。
  final List<T> values;
  final T current;

  /// 当前值的显示文本（尾部 + 无障碍）。
  final String Function(T value) labelOf;

  /// 松手后落盘。
  final ValueChanged<T> onChanged;

  @override
  State<SettingsSliderTile<T>> createState() => _SettingsSliderTileState<T>();
}

class _SettingsSliderTileState<T> extends State<SettingsSliderTile<T>> {
  late int _index = _indexOf(widget.current);

  int _indexOf(T value) {
    final index = widget.values.indexOf(value);
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant SettingsSliderTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改了值（备份恢复、重置等）时跟上。
    if (widget.current != oldWidget.current) {
      _index = _indexOf(widget.current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = widget.values[_index];
    return Padding(
      // 与 M3 单行 ListTile 的内容内边距一致：leading 16dp、trailing 24dp；
      // 上下 8dp 对应含副标题列表项的最小垂直留白。
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(widget.icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      widget.labelOf(value),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const endpointInset = M3ESliderDefaults.thumbRadius;
                    final width = constraints.maxWidth + endpointInset * 2;
                    final height = M3ESliderDefaults.thumbRippleRadius * 2;
                    return SizedBox(
                      height: height,
                      child: OverflowBox(
                        minWidth: width,
                        maxWidth: width,
                        minHeight: height,
                        maxHeight: height,
                        child: Semantics(
                          container: true,
                          slider: true,
                          enabled: true,
                          label: widget.title,
                          value: widget.labelOf(value),
                          increasedValue: widget.labelOf(
                            widget.values[_clampIndex(_index + 1)],
                          ),
                          decreasedValue: widget.labelOf(
                            widget.values[_clampIndex(_index - 1)],
                          ),
                          onIncrease: () => _step(1),
                          onDecrease: () => _step(-1),
                          excludeSemantics: true,
                          child: M3ESlider(
                            key: ValueKey('settings-slider-${widget.title}'),
                            value: _index.toDouble(),
                            min: 0,
                            max: (widget.values.length - 1).toDouble(),
                            divisions: widget.values.length - 1,
                            onChanged: (v) =>
                                setState(() => _index = v.round()),
                            onChangeEnd: (_) => _commit(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _clampIndex(int index) => index.clamp(0, widget.values.length - 1);

  /// TalkBack 上滑/下滑：移动一档并立即落盘（已在端点则不动、不写）。
  void _step(int delta) {
    final next = _clampIndex(_index + delta);
    if (next == _index) return;
    setState(() => _index = next);
    _commit();
  }

  /// 落盘：值没变就不写（点一下没拖动、拖回原档位都不写）。
  void _commit() {
    final value = widget.values[_index];
    if (value != widget.current) widget.onChanged(value);
  }
}
