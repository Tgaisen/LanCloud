import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import 'app_localizations.dart';

/// 应用的本地化 delegate 列表。
///
/// 迁移到 material_ui 后，Material / Cupertino 的本地化必须用新库里的
/// delegate：`flutter_localizations` 提供的是框架版本的类型，material_ui 的
/// 控件（对话框、日期选择器、语义标签……）读不到，中文环境下会静默退回英文，
/// 而且**不会报编译错误**。`GlobalMaterialLocalizations.delegates` 里已经包含
/// Cupertino 与 Widgets 两个 delegate。
///
/// 注意：不能直接改 `app_localizations.dart` 里生成的 `localizationsDelegates`
/// ——那份文件由 `flutter gen-l10n` 生成，构建 / 测试时会被覆盖。
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];
