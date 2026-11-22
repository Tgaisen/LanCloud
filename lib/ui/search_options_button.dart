import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/search_options.dart';
import '../core/search_settings_state.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart' as app_icons;
import 'common.dart';
import 'm3e.dart';

/// 搜索模式下位于 AppBar 最右侧的搜索条件菜单。
class SearchOptionsButton extends StatelessWidget {
  const SearchOptionsButton({super.key, required this.settings});

  final SearchSettingsState settings;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => IconButton(
        tooltip: context.l10n.searchOptions,
        icon: const Icon(app_icons.Icons.tune),
        onPressed: () => showSearchOptionsMenu(
          context,
          anchorContext: anchorContext,
          settings: settings,
        ),
      ),
    );
  }
}

Future<void> showSearchOptionsMenu(
  BuildContext context, {
  required BuildContext anchorContext,
  required SearchSettingsState settings,
}) async {
  final anchor = m3eMenuAnchorOf(anchorContext);
  if (anchor == null) return;
  final l10n = context.l10n;
  await showAdaptiveM3eMultiSelectMenu<SearchOption>(
    context: context,
    anchor: anchor,
    alignEnd: true,
    selected: settings.options.value.enabled,
    items: [
      M3eMenuItem(
        value: SearchOption.matchCase,
        label: l10n.searchMatchCase,
        icon: app_icons.Icons.match_case,
      ),
      M3eMenuItem(
        value: SearchOption.wholeWord,
        label: l10n.searchMatchWholeWord,
        icon: app_icons.Icons.match_word,
      ),
      M3eMenuItem(
        value: SearchOption.regex,
        label: l10n.searchUseRegex,
        icon: app_icons.Icons.regular_expression,
      ),
    ],
    onChanged: (enabled) {
      unawaited(settings.setOptions(SearchOptions.fromEnabled(enabled)));
    },
  );
}
