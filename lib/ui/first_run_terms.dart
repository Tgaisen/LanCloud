import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Icons;
import 'package:flutter/services.dart';

import '../core/agreements.dart';
import '../l10n/l10n.dart';
import 'legal_dialog.dart';
import 'm3e.dart';
import 'system_ui.dart';

/// 首次启动（或条款更新后）的同意页。
///
/// 协议同意和登录是两个独立步骤：勾选协议只改变当前页面的按钮状态，
/// 点击“下一步”后才持久化同意版本并进入登录 / 恢复页。
class FirstRunTerms extends StatefulWidget {
  const FirstRunTerms({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<FirstRunTerms> createState() => _FirstRunTermsState();
}

class _FirstRunTermsState extends State<FirstRunTerms> {
  static const double _wideBreakpoint = 840;
  static const double _contentMaxWidth = 480;
  static const double _buttonMaxWidth = 360;

  bool _agreed = false;
  bool _busy = false;

  Future<void> _continue() async {
    if (!_agreed || _busy) return;
    setState(() => _busy = true);
    try {
      await Agreements.accept();
      if (mounted) widget.onAccepted();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _toggleAgreement() {
    if (_busy) return;
    setState(() => _agreed = !_agreed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeInsets = systemUiSafeInsets(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 沉浸式系统栏：欢迎页在第一帧就显示，导航栏没有主界面那一层兜底。
      value: systemUiOverlayStyleFor(theme.brightness),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideBreakpoint;
            final pagePadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
            final contentHeight = math.max(
              0.0,
              constraints.maxHeight - safeInsets.vertical,
            );
            return SingleChildScrollView(
              // 视口铺满全屏，系统安全区放进滚动内容。回弹时可进入透明
              // 状态栏 / 导航栏区域，而不会被安全区边界提前裁断。
              child: Padding(
                padding: safeInsets,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: contentHeight),
                  child: Padding(
                    padding: EdgeInsets.all(pagePadding),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _brand(context, wide: true),
                                  ),
                                  const SizedBox(width: 48),
                                  SizedBox(
                                    width: _contentMaxWidth,
                                    child: _consent(context, wide: true),
                                  ),
                                ],
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: _contentMaxWidth,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _brand(context, wide: false),
                                    const SizedBox(height: 32),
                                    _consent(context, wide: false),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _brand(BuildContext context, {required bool wide}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/images/logo/app_icon.png',
            width: 88,
            height: 88,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.firstRunWelcome,
          textAlign: textAlign,
          style: context.m3eEmphasizedTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.firstRunMessage,
          textAlign: textAlign,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _consent(BuildContext context, {required bool wide}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linkStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            // 双栏态下协议行跟随主要操作居中，不横向铺满 480dp 分栏。
            constraints: wide
                ? const BoxConstraints(maxWidth: 400)
                : const BoxConstraints(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 只有 Checkbox 本身响应勾选；正文与链接各有独立点击语义。
                Semantics(
                  container: true,
                  label:
                      '${l10n.agreementConsentPrefix}'
                      '${l10n.aboutTerms}'
                      '${l10n.agreementConjunction}'
                      '${l10n.aboutPrivacy}',
                  checked: _agreed,
                  enabled: !_busy,
                  onTap: _busy ? null : _toggleAgreement,
                  child: ExcludeSemantics(
                    child: Checkbox(
                      value: _agreed,
                      visualDensity: VisualDensity.comfortable,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _agreed = value == true),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      key: const ValueKey('agreement-copy'),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            l10n.agreementConsentPrefix,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        _InlineLegalLink(
                          label: l10n.aboutTerms,
                          style: linkStyle,
                          onTap: () => _openLegal(context, LegalDoc.terms),
                        ),
                        ExcludeSemantics(
                          child: Text(
                            l10n.agreementConjunction,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        _InlineLegalLink(
                          label: l10n.aboutPrivacy,
                          style: linkStyle,
                          onTap: () => _openLegal(context, LegalDoc.privacy),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _buttonMaxWidth),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _agreed && !_busy ? _continue : null,
                child: Text(l10n.agreeAndContinue),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : () => SystemNavigator.pop(),
          child: Text(
            l10n.disagreeAndExit,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  void _openLegal(BuildContext context, LegalDoc doc) {
    showLegalDialog(context, doc);
  }
}

class _InlineLegalLink extends StatelessWidget {
  const _InlineLegalLink({
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Text(label, style: style),
      ),
    );
  }
}
