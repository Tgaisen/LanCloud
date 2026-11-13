# Flutter 3.50 升级跟进

> 快照日期：2026-11-13。
> 初始升级提交：`fdc46b8 chore(flutter): 升级至 Flutter 3.50`。

本文记录 LanCloud 升级到 Flutter 3.50 后的临时兼容措施、必须保持的规则和后续清理项。
以后升级 Flutter 3.50.x、Android Gradle Plugin、Material 组件栈或本地化生成器时，
先检查本文是否仍有未关闭的事项。

## 当前基线

| 项目 | 当前值 |
| --- | --- |
| Flutter | `3.50.0` stable |
| Dart | `3.14.0` |
| DevTools | `2.61.0` |
| AGP / Gradle / KGP | `9.5.1` / `9.8.2` / `2.4.21` |
| `material_ui` | `1.11.0` |
| `m3e_core` | `1.1.5` |
| `cupertino_ui` | `1.1.6` |

Flutter 3.50 的最低 Android 构建要求低于项目当前工具链。但项目使用的 AGP 和 Gradle
高于 Flutter 3.50 源码当时标出的已知测试上限（AGP 9.4、Gradle 9.5.0）。当前 debug
构建通过，但后续升级 Gradle 时不要假设 Flutter 工具链已经覆盖该版本。

## 已完成事项

- `pubspec.yaml` 固定 Flutter `3.50.0`，Dart 约束提升到 `^3.14.0`。
- `pubspec.lock` 已用 Dart 3.14 重新生成。
- 业务界面继续使用 `material_ui` / `m3e_core` / `cupertino_ui`，没有回退到框架内
  Material / Cupertino 导入。
- `lib/l10n/delegates.dart` 继续作为应用本地化的唯一入口，并使用
  `material_ui` 的新 `GlobalMaterialLocalizations.delegates`。该列表已经包含
  `cupertino_ui` 的新 `GlobalCupertinoLocalizations`。
- Android `profile` 的独立包名改用 AGP Variant API 设置，避免 Flutter 3.50.0
  把应用专属的 `applicationIdSuffix` 复制给插件库。
- 全量测试 899 个用例通过，debug APK 构建通过。

## 本地化生成器兼容

### 现象

Flutter 3.50.0 的 `gen-l10n` 模板仍从 `flutter_localizations` 生成：

- `GlobalMaterialLocalizations`
- `GlobalCupertinoLocalizations`

这两个类在 3.50 已标记为过时，因此生成的
`lib/l10n/app_localizations*.dart` 会产生 `deprecated_member_use`。上游问题：
[flutter/flutter#196475](https://github.com/flutter/flutter/issues/196475)。

### 当前处理

- 不能手工修改生成文件；`flutter gen-l10n` 会覆盖，CI 也会检查生成结果。
- 应用运行时不使用生成类中的 `AppLocalizations.localizationsDelegates`，而是使用
  `lib/l10n/delegates.dart` 的 `appLocalizationsDelegates`。
- `l10n.yaml` 通过生成头添加了带原因的 `deprecated_member_use` 窄范围豁免。
  该豁免只处理上游模板仍输出的旧 delegate，不覆盖业务 Dart 文件。

### 上游修复后的清理

1. 检查新的 `gen-l10n` 模板是否改为从 `material_ui` / `cupertino_ui` 生成 delegate。
2. 删除 `l10n.yaml` 的 `header` 兼容配置。
3. 运行 `tools\agent.cmd gen`，确认生成文件不再引用旧 delegate。
4. 运行 `tools\agent.cmd analyze`，确认不需要任何 `deprecated_member_use` 豁免。
5. 保持在 `lib/l10n/delegates.dart` 中使用新组件栈的 delegate。

## Android profile 包名兼容

### 现象

Flutter 3.50.0 会把 app 的 build type 通过 `initWith` 复制到插件库。如果
`profile` build type 设置 `applicationIdSuffix = ".profile"`，任意原生插件库都会
报：

```text
Library projects cannot set applicationIdSuffix
```

上游问题：[flutter/flutter#196412](https://github.com/flutter/flutter/issues/196412)。

### 当前处理

- `android/app/build.gradle.kts` 不在 `profile` build type 上设置
  `applicationIdSuffix`。
- 在 `androidComponents.onVariants` 中，仅对 profile variant 设置：
  `com.lancloud.lancloud.profile`。
- debug 继续使用 `com.lancloud.lancloud.debug`，release 使用
  `com.lancloud.lancloud`。

### 后续检查

- 每次升级 Flutter 3.50.x 后至少构建一次 profile APK，确认包名仍为
  `com.lancloud.lancloud.profile`。
- 上游修复后可以评估是否恢复 buildType 写法；Variant API 方案本身有效，
  如果保留，应继续在注释中记录原因。
- 不要只验证 debug 配置；这个问题最初会在 debug 任务配置阶段触发，但最终必须验证
  profile 产物。

## Material 组件栈规则

`material_ui`、`m3e_core`、`cupertino_ui` 必须作为一组升级，但不再设置固定的
`material_ui <1.8.0` 上限。历史上 `material_ui` 1.8 的 `RoundedPolygon` 与
`m3e_core` 1.1.4 存在同名类型冲突；当前已使用 `material_ui 1.11.0` 和
`m3e_core 1.1.5`，分析通过。

后续升级这组依赖时：

- 保持三者版本配套，避免只推进其中一个。
- 检查 `RoundedPolygon`、`ColorScheme`、主题和本地化 delegate 是否出现同名类型冲突。
- 运行 `tools\agent.cmd format`、`analyze`、`test`。
- Dependabot 继续把三者放在同一组中更新，不再对整个 `material_ui` 版本范围做忽略。

## 每次升级 3.50.x 的检查清单

1. 更新 `pubspec.yaml` 中精确的 Flutter 版本。
2. 运行 `tools\agent.cmd pubget` 生成锁文件。
3. 运行 `tools\agent.cmd gen`，确认本地化生成 diff 可重复。
4. 运行 `tools\agent.cmd format`、`analyze`、`test`。
5. 运行 `tools\agent.cmd build-apk`，并核对 debug 包名与 versionCode。
6. 手动构建 profile，核对 `com.lancloud.lancloud.profile`。
7. 通过 CI 覆盖 Android release/冷启动和 Windows release/启动冒烟。
8. 人工回归网页登录 WebView、分享 Intent、后台传输通知、生物识别和 Windows 拖放。

## 仍需留意

- `desktop_drop` 和 `m3e_core` 仍会触发 KGP 未来兼容警告。
- `flutter_inappwebview 6.2.0-beta.3` 的 Android / Windows 原生路径需要通过实机回归。
- iOS 不在当前产品验收范围内，升级 Flutter 不改变这一约定。
- OHOS 仍固定在自己的 Flutter 3.47 社区适配线，不要与官方 Flutter 3.50 升级混在一起。
