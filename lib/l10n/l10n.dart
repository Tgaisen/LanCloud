import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// 快捷访问当前语言的本地化文案：`context.l10n.xxx`。
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
