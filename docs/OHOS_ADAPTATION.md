# HarmonyOS NEXT / OpenHarmony 适配与发版指南

> 文档状态：适配方案草案；主平台发布 CI 已落地，OHOS 构建与发布仍待实施。
>
> 更新日期：2026-10-19。
>
> 适用项目：LanCloud（Flutter 客户端，当前主要支持 Android、Windows）。

## 1. 背景与目标

### 1.1 当前项目基线

- 当前代码基线使用 Flutter 3.47.7、Dart SDK `^3.13.4`。
- 业务、状态管理、网络、模型、本地化和绝大多数界面均在 Dart 层，Android、iOS、Windows 只负责平台入口和系统能力。
- 仓库当前没有 `ohos/` 工程，也未完成过 HAP 构建。
- Android 侧现有约 9 个自定义 MethodChannel，负责安装、文件选择、SAF、分享、权限、链接、外部链接、系统信息和拖拽等能力。
- CI 会在 PR 和推送到 `main` 时执行格式检查、`flutter analyze` 和 `flutter test`；推送到 `main` 后，Release workflow 还会检查版本，未发布时构建 Android/Windows 产物并创建 draft Release，详见 [CI_RELEASE.md](CI_RELEASE.md)。
- 版本号规则见 [VERSIONING.md](./VERSIONING.md)。当前版本号中包含 Android ABI 位，不能直接照搬为 HAP 的 versionCode。

### 1.2 结论

该项目适合采用 **Flutter-on-OHOS** 路线，不建议用 ArkTS 重写全部产品和 UI。

总体判断：

- 难度：中等偏上；完成核心 PoC 后预计为中等。
- 产品业务和 UI 可以保持一套源码。
- 平台入口、ArkTS 工程、插件依赖和构建发布流程需要一套独立适配。
- 不应维护两套完整 App，但需要承受“双平台构建、双平台回归”的维护成本。
- 在正式投入前，必须完成 HAP 构建和关键链路的真机验证。

最需要提前验证的能力：

1. 网页登录和 Cookie 读取。
2. 账号安全存储与本地数据库。
3. 文件选择、下载、打开、分享和用户目录授权。
4. 后台传输。
5. 分享入口、深链和通知。
6. HAP 签名、安装和更新路径。

### 1.3 不在本文范围内

- 使用 ArkTS 重写全部 Flutter UI。
- 将 Android APK 直接安装到 HarmonyOS NEXT。
- 在首版同时支持所有历史 HarmonyOS NEXT API 版本。
- 继续使用 Android APK 的自动更新机制更新 HAP。

### 1.4 当前自动化状态

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| 格式、分析、共享测试 | 已落地 | `ci.yml` 在 PR 和 main 推送时运行 |
| Android Release 构建 | 已落地并跑通 | `release.yml` 使用 Ubuntu runner 构建三个 APK |
| Windows Release 构建 | 已落地并跑通 | `release.yml` 使用 `windows-latest` 构建便携版 ZIP |
| Android Release 签名 | 已落地 | 从 GitHub Secrets 注入 keystore，并校验证书指纹 |
| Android/Windows draft Release | 已落地并跑通 | 推送 main 且版本尚未发布时自动构建并创建 draft |
| `main` 到 `ohos` 自动同步 | 未实施 | 暂无 `ohos` 分支和同步 workflow |
| OHOS CI、HAP 构建与签名 | 未实施 | 尚无专用 runner、HAP 构建任务和签名配置 |
| 本项目 HAP 真机验证 | 未完成 | 依赖兼容矩阵目前仍属于待验证方案 |

## 2. 技术路线与工具链

### 2.1 推荐路线

使用 OH-Flutter 社区维护的 Flutter OpenHarmony 分支构建 HAP，继续复用现有 Dart 业务和 UI 代码。

- Flutter OH 仓库：<https://gitcode.com/oh-flutter/flutter_flutter>
- 参考标签：`3.47.7-ohos-1.0.0`
- 该标签声明的本版本配套：
  - DevEco Studio 26.0.0
  - Command Line Tools 26.0.0
  - 引擎构建最低 API：OpenHarmony API 26.0.0
  - 应用目标 API：OpenHarmony API 26.0.0
  - 应用最低运行 API：OpenHarmony API 26.0.0

OH-Flutter 是社区适配线，不是 Google 官方 Flutter 支持。正式项目应固定到具体 tag，不跟 `oh-3.47-dev` 等开发分支滚动升级。

### 2.2 版本与兼容性说明

- `3.47.7-ohos-1.0.0` 的框架标签与 Flutter 3.47.7 对齐，但仍属于较新的社区发布。
- 3.47.7 相对 3.47.5 的上游改动集中在 iOS，OHOS 引擎工件复用了 3.47.5 批次；不能把标签更新理解为 OHOS 引擎重新成熟了一轮。
- API 26 最低运行要求会排除较早的 HarmonyOS NEXT 设备。是否接受这一限制需要产品侧明确决策。
- Flutter OH 版本和项目版本必须一起记录在构建信息中，不能只记录应用版本号。

### 2.3 建议的本机/CI 环境

需要准备：

- Flutter OH 3.47.7 标签对应的 SDK。
- DevEco Studio 26.0.0 或对应的 Command Line Tools。
- HarmonyOS API 26 SDK。
- `ohpm`、`hvigor`、`hdc`。
- Node.js、Git、JDK 及项目现有的 Android/Windows 构建依赖。

关键环境变量：

```text
DEVECO_SDK_HOME=<HarmonyOS SDK 目录>
FLUTTER_STORAGE_BASE_URL=https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com
```

环境搭建后应满足：

```text
flutter --version
# 应显示 3.47.7-ohos-1.0.0

flutter doctor -v
# HarmonyOS toolchain 应为可用状态

flutter devices
# 应能识别 HarmonyOS 真机或模拟器
```

### 2.4 首个 HAP 构建

先在独立实验分支或临时工程中验证，不直接修改正式发布配置。

```text
flutter create --platforms ohos <临时项目>
flutter pub get
flutter build hap --debug
flutter build hap --release
flutter install -t <device-id> <hap 路径>
```

如果已有项目增加 OHOS 目标，应在临时工程中对比 OHOS 模板，确认 `ohos/`、应用标识、图标、权限、签名和权限文案均已正确配置。

常见排障方向：

- 切 SDK 或存储镜像后清理 `bin/cache` 和项目构建缓存。
- debug VM snapshot 不匹配时执行 `flutter clean` 后重新构建。
- 确认 DevEco/API 版本与 Flutter OH 标签的要求一致。
- 确认 `ohos.permission.INTERNET` 等基础权限已经声明。

## 3. 代码结构与平台抽象

### 3.1 目标结构

```text
lib/
  core/                 # 共享业务、API、模型、存储和平台能力接口
  ui/                   # 共享 Flutter UI
  l10n/                 # 共享本地化

android/                # Android 平台入口和通道实现
ios/                    # iOS 平台入口
windows/                # Windows 平台入口
ohos/                   # HarmonyOS/ArkTS 工程（适配后新增）
```

`main` 是产品源码主线，`ohos` 是下游平台集成分支。鸿蒙分支不应复制一份 `lib/` 业务代码。

### 3.2 平台能力抽象

当前 `PlatformSupport` 已集中了部分平台判断，但仍需要在适配前补充能力边界：

- 增加 `isOhos`，但不能简单把 OHOS 加入 `isMobile` 后假定所有移动能力都存在。
- 区分能力而不是只判断平台，例如：
  - `supportsWebLogin`
  - `supportsSecureStorage`
  - `supportsBackgroundTransfer`
  - `supportsUserSelectedDownloadDirectory`
  - `supportsSystemShare`
  - `supportsDeepLinks`
  - `supportsBiometricAuth`
  - `supportsDynamicColor`
- 平台专属实现放在 `lib/core/platform/<platform>/` 或等价目录中，共享 UI 只调用接口。
- 共享代码中避免直接 import `local_auth_android`、`local_auth_darwin`、Windows 专用 FFI 包等平台实现。
- 避免在页面中散落 `PlatformSupport.isHarmony`；平台差异由能力接口或完整的功能适配器承担。

### 3.3 首批适配器建议

| 适配器 | 负责能力 |
| --- | --- |
| WebAuthAdapter | 内嵌浏览器、Cookie 读取、WebView 配置 |
| SecureStoreAdapter | 账号 Cookie、WebDAV 密码等敏感数据 |
| DatabaseAdapter | 数据库打开、迁移、站点/传输记录持久化 |
| FileGateway | 文件选择、目录选择、保存、打开、删除 |
| ShareGateway | 系统分享、分享入口、深链 |
| BackgroundTaskAdapter | 传输期间的后台保活和生命周期 |
| NotificationAdapter | 通知初始化、权限、渠道、进度和完成提醒 |
| UpdateAdapter | Android/Windows 更新与 HarmonyOS 更新策略 |

## 4. 三方依赖兼容矩阵

以下是首次适配的候选方案。表中的版本来自 2026-10-19 可查到的社区适配仓库，必须通过实际 HAP 构建和真机测试后才能标记为“已验证”。

OpenHarmony 三方库总表：<https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.md>

| 依赖 | 项目当前版本 | OHOS 候选实现 | 适配动作与风险 |
| --- | --- | --- | --- |
| `flutter_inappwebview` | `6.2.0-beta.3` | `6.1.5-ohos-1.0.1` | 需要从 beta 版本对齐到稳定分支；已声明支持 `CookieManager.getCookies`，但仍需验证网页登录和多域名 Cookie |
| `flutter_secure_storage` | `9.2.4` | `fluttertpc_flutter_secure_storage` 的 `9.2.4-ohos-1.0.0` / `flutter_secure_storage_ohos` | pub.dev 主包不声明 OHOS，必须使用 CPF 适配实现；不要把敏感数据降级为明文偏好存储 |
| `sqflite` | `2.4.4` | `2.4.2-ohos-1.0.0` | 版本接近，运行数据库迁移和并发读写测试；Windows 的 FFI 分支不要带到 OHOS |
| `file_picker` | `8.3.3` | `file_picker_ohos` `10.3.8-ohos-1.0.0`，或旧版 `8.0.6` | 需要选择版本并调整 import/API；目录选择模式存在已知限制，下载目录授权需要单独实现 |
| `open_filex` | `4.7.0` | `4.7.0-ohos-1.0.0` | 版本匹配，优先验证本地文件打开和 URI 权限 |
| `receive_sharing_intent` | `1.9.0` | `1.8.1-ohos-1.0.0` | 小版本回退，验证冷启动、热启动和多文件分享 |
| `local_auth` | `3.0.2` | OHOS `local_auth 3.0.2` 适配分支/提交 | 需要固定 tag 或 commit；同时移除共享代码对 Android/Darwin 实现包的直接依赖 |
| `path_provider` | `2.1.6` | OHOS `path_provider` 2.1.5 适配 | 验证应用文档、缓存、临时目录和下载目录语义 |
| `shared_preferences` | `2.5.5` | OHOS `shared_preferences` 2.5.4 适配 | 版本接近，确认初始化时机和数据类型兼容 |
| `url_launcher` | `6.3.2` | OHOS `url_launcher` 6.3.2 适配 | 外部链接使用系统浏览器，自定义 scheme 需要单独测试 |
| `flutter_local_notifications` | `22.3.1` | `22.0.1-ohos-1.0.0-beta.1` | 当前项目主要使用 `show/cancel`，基础通知可用；需要补 OHOS 初始化和通知详情，进度/常驻/定时能力有限制 |
| `flutter_foreground_task` | `11.0.3` | 适配中 | 不能作为首版硬依赖；先规划前台传输降级，或实现 ArkTS 持续任务适配 |
| `desktop_drop` | `0.8.4` | `0.6.1-ohos-1.0.0` | 版本差较大；移动端不是核心功能，可作为非阻塞项或关闭 |
| `dynamic_color` | `2.1.0` | 无必要适配 | 在 OHOS 上像 Windows 一样禁用/降级为固定主题 |
| `m3e_core` | `1.1.4` | Dart 组件可复用 | 触觉反馈通道可能需要降级；与 Material UI 包名一起验证 |
| `material_ui` / `cupertino_ui` | `1.6.0` / `1.1.2` | OHOS SDK 仍包含 `flutter/material.dart`、`flutter/cupertino.dart` | 可使用本地包名映射/shim；不要直接假定第三方包中的 `TargetPlatform` switch 已覆盖 `ohos` |

### 4.1 依赖管理规则

- OHOS 适配依赖固定到 tag；没有 tag 时固定 commit，不使用移动分支。
- 不混用官方包和鸿蒙包中互不配套的版本。
- 所有 OHOS 覆盖尽量集中在一个可审计的依赖文件或生成脚本中。
- `pubspec.lock` 不作为手工解决冲突的目标，冲突时在当前 SDK 下重新解析。
- 每次升级 OHOS Flutter SDK 或关键插件，都重新跑 HAP 构建和核心冒烟测试。
- 引入三方 fork 前检查许可证、最近提交时间、issue 状态和维护者响应能力。

## 5. 功能适配清单

| 功能 | 复用程度 | 主要工作 | 优先级 |
| --- | --- | --- | --- |
| 网络/API/模型/本地化 | 高 | 基本无需改写 | P0 |
| 账号和密码存储 | 高 | 接入 OHOS 安全存储实现 | P0 |
| 本地数据库 | 高 | 接数据库适配层并跑迁移测试 | P0 |
| 网页登录 | 中高 | WebView 插件对齐、Cookie 读取、登录跳转 | P0 |
| 文件上传 | 中 | 文件选择适配、路径权限、长文件名 | P0 |
| 文件下载 | 中 | 应用沙箱下载、用户目录选择、文件打开 | P0 |
| 分享和打开链接 | 中 | 分享 Intent、深链、冷/热启动收件箱 | P1 |
| 本地通知 | 中 | OHOS 初始化、渠道、基础通知和权限 | P1 |
| 生物识别 | 中 | 适配 `local_auth`，验证取消/不可用错误码 | P1 |
| 主题/动态取色 | 高 | 动态取色降级，检查安全区和系统栏 | P1 |
| 扫描二维码/拍照 | 中 | 图片选择可复用，系统相机通道可能需要 ArkTS 实现 | P1 |
| 后台传输 | 低到中 | 前台服务/持续任务、后台策略、通知联动 | P2 |
| HAP 应用更新 | 低 | 应用市场或独立下载安装方案，不能复用 APK 更新 | P2 |
| 桌面拖拽 | 低 | 可选能力；版本不匹配时关闭 | P3 |

建议首版优先保证 P0/P1 的可用性。后台传输可以作为单独里程碑，不应阻塞其他核心功能的验证。

## 6. Android 自定义通道与 OHOS 映射

| 当前通道 | 当前用途 | OHOS 方案 |
| --- | --- | --- |
| `lancloud/installer` | 安装 APK | HAP 不支持 APK 安装；改为应用市场/合法安装流程，或禁用该入口 |
| `lancloud/file_picker` | Android 文件选择和拍照 | 文件选择优先用适配后的 `file_picker`；相机、目录选择另做 ArkTS 适配 |
| `lancloud/saf` | Android SAF 目录授权和文件复制 | 使用 OHOS DocumentViewPicker/文件框架；下载目录和 URI 权限需要单独设计 |
| `lancloud/share` | 系统分享文本/文件 | 使用 OHOS 分享 Kit 或适配后的分享插件 |
| `lancloud/permissions` | Android 通知、安装、电池优化等权限 | 抽象为能力权限；OHOS 只保留真实有对应语义的权限 |
| `lancloud/links` | 打开蓝奏云链接、冷启动链接 | 使用 OHOS Ability/URI 入口和深链插件，补充冷/热启动测试 |
| `lancloud/external_link` | Android Custom Tabs | 使用 OHOS 系统浏览器和 `url_launcher` 适配 |
| `lancloud/system` | Android SDK、ABI、系统动画状态 | 只实现 UI/生命周期真正需要的子集，不照搬 Android 字段 |
| `lancloud/drag_drop` | Windows 文件拖入 | 先关闭；若 OHOS 桌面形态需要，再接入适配插件 |
| `lancloud/window` | Windows 窗口明暗 | 仅 Windows 保留 |

适配原则：

- 能由成熟插件覆盖的通道，优先删除自定义实现。
- 只有 Android 语义的错误码不能直接暴露给 OHOS 页面。
- 平台不支持的入口必须在 UI 上明确隐藏或降级，不静默失败。

## 7. 分支与同步策略

### 7.1 分支角色

- `main`：唯一产品源码主线，负责共享业务、界面、测试和 Android/Windows 构建。
- `ohos`：下游集成分支，负责 `ohos/`、ArkTS 实现、OHOS 依赖覆盖、HAP 构建和签名配置。
- 需要时可以创建短期 release 分支，但不长期保留多套产品源码。

### 7.2 同步规则

1. 共享代码只从 `main` 进入 `ohos`。
2. 使用合并而不是长期 rebase，避免重写已发布历史和破坏 CI 追踪。
3. 推荐按日或按批次自动创建 `main -> ohos` 同步 PR；至少在每次 RC 前同步。
4. 不要在 `ohos` 分支上单独修共享业务逻辑；若必须修，先落到 `main`，再同步。
5. OHOS 专属修复放在平台目录；涉及公共接口的修改要回写到 `main` 的抽象层。
6. 每个 ohos 提交记录对应的 main 提交、Flutter OH 版本和插件 tag。

### 7.3 冲突高发文件

- `pubspec.yaml`
- `pubspec.lock`
- `material_ui` / `cupertino_ui` shim
- 平台抽象接口文件
- `PlatformSupport`
- 通知初始化和更新服务

降低冲突的方式是减少 `ohos` 分支对共享文件的修改，而不是要求每次发版时人工解决大量冲突。

## 8. 发版流程

### 8.1 版本策略

- 产品版本号共用，例如 `26.2.0`。
- Android、Windows、OHOS 可以有各自的构建号。
- HAP 的 versionCode 需要独立、单调递增；不要复用 Android 的 ABI 编码。
- 建议 tag：
  - `main`：`v26.2.0`
  - OHOS 集成分支：`ohos-v26.2.0` 或 `v26.2.0-ohos.1`
- OHOS 包内应包含：
  - 产品版本
  - main 源码 tag/commit
  - OHOS 分支 commit
  - Flutter OH SDK tag
- 如果同一 Release 页面同时挂 APK、ZIP 和 HAP，发布说明必须注明 HAP 对应的 OHOS tag/source commit。
- 当前主平台发布 CI 会在 Android/Windows 构建成功后才创建或补齐 `v<版本>` tag 和 Release；如果版本已经正式发布，后续推送会跳过构建。

### 8.2 已实现的主平台发布流程

当前由 [.github/workflows/release.yml](../.github/workflows/release.yml) 驱动，并复用 [tools/release/](../tools/release/) 下的拆分脚本。详细配置见 [CI_RELEASE.md](./CI_RELEASE.md)。

1. 在 `main` 更新版本号，确认 `pubspec.yaml` 与 `lib/core/app_info.dart` 一致，然后推送。
2. `Release` workflow 的 `validate` job 校验版本、tag/Release 状态，并执行格式检查、静态分析和测试。
3. 版本尚未发布时，`android` 和 `windows` 两个 job 并行构建产物并上传 Actions artifact。
4. `release` job 下载产物，调用 `tools/release/publish.ps1` 创建或补齐 draft Release。
5. tag 不存在时，`publish.ps1` 在产物齐全后创建并推送 `v<版本>` tag。
6. 在 GitHub Releases 页面检查四个产物和发布说明，人工点击发布。

如果版本已经正式发布，workflow 会输出 `should_release=false` 并跳过后续构建；如果同名 Release 仍是 draft，可以重跑 workflow 补齐或替换产物。

`tools/release.ps1` 仍然保留为本地一键发布入口，但不再是唯一发布路径。它和 CI 使用同一组校验、构建和发布脚本：

- `tools/release/validate.ps1`
- `tools/release/build_android.ps1`
- `tools/release/build_windows.ps1`
- `tools/release/publish.ps1`

### 8.3 OHOS 接入后的目标流程

1. 在 `main` 完成版本号和发布 CI 流程。
2. 将同一个 `v<版本>` tag 合并到 `ohos` 分支。
3. 在 OHOS 专用 runner 执行依赖解析、格式检查、静态分析和共享测试。
4. 构建 debug/release HAP，执行签名与校验和检查。
5. 运行鸿蒙真机回归矩阵，至少覆盖本文第 10 节验收项。
6. 通过后创建 `ohos-v<版本>` 下游 tag，并上传 HAP、校验和及构建信息。
7. 通过人工发布门禁后发布，或将 HAP 作为已审阅主 Release 的附加资产。

如果 OHOS 验证失败，可以单独延迟 HAP 发布，但不能把未验证的 HAP 和同版本 APK 一起发布。

### 8.4 预发布版本

- 每次 `snapshot/pre/beta/rc` 都构建内部 HAP 是可取的。
- 不建议每个预发布都做完整应用市场发布，避免维护和审核成本过高。
- 稳定版和 RC 必须做完整回归；普通 snapshot 可以只跑核心冒烟测试。
- 安全修复、账号登录修复和文件损坏修复应立即同步到 OHOS。

### 8.5 热修复

- 修复共享代码：在 `main` 修复、发 patch tag，再合并到 `ohos`。
- 修复 OHOS 专属问题：在 `ohos` 修复并打 OHOS patch tag，同时评估是否需要补公共接口。
- 禁止长期只在 OHOS 分支存在业务修复，避免版本语义分叉。

### 8.6 更新通道

当前 `UpdateService` 只支持 Android 和 Windows，HAP 不应继续走 APK 更新逻辑。

需要产品侧选择：

- 应用市场更新。
- 应用内引导到合法下载页，再完成签名 HAP 安装。
- 首版隐藏自动更新入口，仅提供版本信息和手动安装说明。

无论选择哪种方式，都必须：

- 版本号单调递增。
- 签名证书稳定。
- 不显示指向 APK 的更新链接。
- 在 HAP 资产真正上传成功前，不向 OHOS 用户提示“有新版本”。

## 9. CI/CD 与自动化

### 9.1 现有 CI

当前 GitHub Actions 已包含两条主线：

1. [ci.yml](../.github/workflows/ci.yml)
   - 在 PR 和推送 main 时运行。
   - 使用官方 Flutter 3.47.7。
   - 执行 `dart format --set-exit-if-changed`、`flutter analyze`、`flutter test`。
2. [release.yml](../.github/workflows/release.yml)
   - 每次推送 main 都检查版本，也支持 `workflow_dispatch`。
   - jobs：`validate` → `android` / `windows` → `release`。
   - Android 使用 GitHub Secrets 中的 keystore 构建三个 APK，并校验证书 SHA-256。
   - Windows 使用 `windows-latest` 构建便携版 ZIP。
   - 产物通过 Actions artifacts 在 job 之间传递，再创建或补齐 draft Release。
   - 默认创建 draft；手动触发可显式选择是否 draft。
   - 使用 `concurrency: release-main` 防止并发发布冲突。

这已经覆盖共享 Dart 代码和 Android/Windows 的主发布链，但还不能构建 HAP。

### 9.2 OHOS CI 的接入方式

建议先使用独立 `ohos-release.yml`，避免 HAP 构建还不稳定时阻塞 Android/Windows 发布；等 HAP 流程稳定后，再通过 `workflow_call` 或 `workflow_run` 接入主 Release。

建议的 OHOS workflow 分成：

1. `validate-ohos`：确认主版本 tag 已经合并到 `ohos`，解析 Flutter OH SDK 和插件版本。
2. `test-ohos`：OHOS Flutter SDK 下执行格式、分析和共享测试。
3. `build-ohos`：构建 debug/release HAP，签名、校验并计算 SHA-256。
4. `publish-ohos`：在人工审批后创建 `ohos-v<版本>` tag 和 Release，或把 HAP 上传到已批准的主 Release。

另建 `ohos-sync.yml` 做每日/手动同步 PR：

1. checkout `main` 和 `ohos`。
2. 将 `main` 合并到 `ohos`，无冲突则推送同步分支或 PR。
3. 有冲突时只创建 PR 并通知维护者，不自动解决语义冲突。
4. 发布前校验 `v<版本>` tag 是 `ohos` 分支的祖先。

HAP 构建需要 DevEco Studio、HarmonyOS SDK、`ohpm`、`hvigor`、`hdc` 和签名材料。当前 GitHub Actions 主发布使用托管 Ubuntu/Windows runner；OHOS job 应使用专用的自托管 runner，或在 GitCode 侧建立等价 CI。不能假定标准 GitHub runner 已具备这些环境。

### 9.3 可以自动化的内容

- 已实现：版本/tag/Release 状态检查。
- 已实现：Android/Windows 并行构建和 artifact 传递。
- 已实现：Android 签名校验、SHA-256 输出和 draft Release 创建。
- 自动创建 main → ohos 同步 PR。
- 合并无冲突且构建通过的同步变更。
- 运行共享测试、OHOS 相关测试和静态分析。
- 固定版本 SDK 下的 HAP 构建。
- 自动签名、校验签名和生成 SHA-256。
- 上传 HAP 和构建元数据。
- 检查依赖 tag、Flutter OH tag 和版本号是否变化。
- 失败时通知维护者。

### 9.4 不应完全自动化的内容

- 新系统能力的语义实现。
- WebView Cookie、后台任务、文件目录权限等真机行为验证。
- 复杂共享文件的冲突裁决。
- 发布签名私钥的管理和发布批准。
- 应用市场合规、隐私声明和人工验收。

自动合并只能处理没有冲突的同步；冲突或平台语义变化必须由维护者处理。

### 9.5 签名和密钥

- HAP 签名证书和密钥不得进入 Git。
- Android 目前通过 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 四个 GitHub Secrets 注入签名材料。
- HAP 签名材料应使用独立 GitHub Environment/GitCode Secret，不与普通 PR 构建环境共享。
- 当前 `release.yml` 在 workflow 级别声明了 `contents: write`；接入自托管 OHOS runner 前，建议把写权限和环境审批进一步收窄到发布 job。
- HAP 发布只允许从受保护 tag 或受保护 Environment 触发。
- 构建日志中不得打印证书内容、密码或完整签名配置。
- 上传产物同时记录证书指纹和校验和。

## 10. 测试与验收

### 10.1 自动化测试

- 共享测试必须分别在官方 Flutter 3.47.7 和 Flutter OH 3.47.7 下运行。
- 对 `TargetPlatform.ohos` 分支增加单元/组件测试，避免平台 switch 漏分支。
- 通道协议测试：Dart 方法名、参数和 ArkTS 返回值保持一致。
- 数据库迁移测试：沿用现有迁移测试，增加 OHOS 新安装和升级场景。
- 发布前检查产物内是否包含预期的 OHOS 插件和权限。

### 10.2 真机验收清单

- [ ] HAP debug 构建成功。
- [ ] HAP release 构建、签名和安装成功。
- [ ] 网页登录可完成，能读取 `ylogin`、`phpdisk_info` 等必要 Cookie。
- [ ] 账号 Cookie 能安全保存并在重启后恢复。
- [ ] WebDAV 密码不落明文。
- [ ] 数据库迁移、账号数据和传输记录正常。
- [ ] 多文件上传可用，取消上传不留下损坏记录。
- [ ] 下载到应用沙箱可用。
- [ ] 下载到用户选择目录可用，或明确降级并隐藏入口。
- [ ] 文件打开、分享、删除和重名处理正常。
- [ ] 分享链接/文件到应用，冷启动和热启动都能进入正确页面。
- [ ] 通知权限、基础通知、点击跳转正常。
- [ ] 生物识别取消、失败、无凭证等错误路径正常。
- [ ] 系统栏、键盘、安全区、返回手势和页面转场正常。
- [ ] 后台/前台传输行为符合产品承诺。
- [ ] 旋转、折叠屏、分屏和窗口尺寸变化不崩、不白屏。
- [ ] Android 和 Windows 没有因 OHOS 依赖或平台抽象改动而回归。

### 10.3 建议设备矩阵

- API 26 最低支持真机。
- 当前主流 HarmonyOS API 版本真机。
- 至少一台平板/折叠屏或可调整窗口设备。
- 模拟器仅用于开发，不作为最终验收依据。

## 11. 风险登记

| 风险 | 影响 | 缓解措施 |
| --- | --- | --- |
| OH-Flutter 3.47.7 标签较新 | 可能存在未暴露的引擎或工具链问题 | 固定 tag；先在独立分支构建；保留可回退的旧 tag |
| API 26 最低运行要求 | 排除部分旧 NEXT 设备 | 产品确认目标设备范围；若必须支持旧版本，重新评估 SDK |
| 三方库兼容表主要验证到 3.35 | 3.47.7 下可能出现编译或运行差异 | 建立依赖兼容矩阵；每个关键链路单独跑 HAP 实机测试 |
| 后台任务插件仍在适配 | 后台传输可能中断或无保活能力 | 首版降级为前台传输；单独评估 ArkTS 持续任务 |
| 文件目录选择限制 | 用户无法选择任意下载目录 | 首版使用沙箱目录；另做 DocumentViewPicker 适配 |
| HAP 更新体系与 APK 不同 | 现有更新功能无法直接复用 | 单独设计市场更新或合法下载安装流程 |
| 社区 fork 维护不稳定 | 依赖修复、安全和版本更新不可控 | 固定 tag/commit；尽量把平台能力收口到适配器；必要时自行维护 patch |
| 通知能力不等价 | 进度、常驻、定时通知可能不一致 | 首版只承诺基础通知；页面中隐藏不支持的选项 |
| WebView PlatformView 性能/白屏 | 登录页和分享浏览可能异常 | 实测长页面、滚动、键盘和旋转；保留原生兜底方案 |
| 平台分支长期偏离 | 共享修复被分裂成两套 | `main` 为唯一源码源；定期自动同步；禁止业务代码只改 ohos |
| 构建环境不可复现 | 不同机器产出的 HAP 行为不同 | 固定 SDK/插件 tag；CI 构建；记录构建元数据和校验和 |

## 12. 推荐实施阶段与工作量

以下为一名熟悉 Flutter、ArkTS 和 CI 的开发者的粗略估算，不包含应用商店审核等待：

### Phase 0：技术验证

目标：证明能构建、安装并运行 HAP。

- 搭建 Flutter OH、DevEco、API 26 环境。
- 构建空 HAP。
- 验证 WebView 登录、安全存储和数据库最小闭环。
- 建立依赖兼容矩阵。

预计：约 1 周。

### Phase 1：核心功能 MVP

目标：登录、浏览、上传、下载、打开/分享文件和基础设置可用。

- 接入 WebView、安全存储、SQLite、文件选择、打开文件。
- 增加 OHOS 平台适配器和必要通道。
- 运行共享测试。

预计：约 3–5 周。

### Phase 2：平台与体验补齐

目标：补齐分享入口、深链、通知、生物识别、主题和平台交互。

- 分享/深链冷热启动。
- OHOS 通知详情和点击跳转。
- 安全区、返回、旋转和折叠屏。
- 动态取色降级。

预计：约 2–3 周。

### Phase 3：后台传输与发布

目标：达到可持续发布状态。

- `flutter_foreground_task` 完成后接入，或实现受控的 OHOS 持续任务。
- HAP 签名、版本号、更新策略。
- 在已完成的主平台 Release CI 上增加 OHOS CI、HAP 签名和发布门禁。
- 真机回归和发布文档。

预计：约 2–4 周。

整体估算：约 6–10 周。若后台传输暂缓、首版只做前台传输，可以缩短首版周期；若关键插件在 3.47.7 下出现兼容问题，则需要增加缓冲时间。

## 13. 立项前检查清单

- [x] 主平台 CI 与 draft Release 流程已经跑通。
- [ ] 确认 HarmonyOS 目标设备的 API 最低版本为 26。
- [ ] 确认可以接受 HAP 使用独立的应用安装/更新流程。
- [ ] 确认 `ohos` 分支作为 main 的下游分支，而不是复制一套产品代码。
- [ ] 确认使用 OH-Flutter 3.47.7 的固定 tag。
- [ ] 完成 WebView 登录和 Cookie 的真机验证。
- [ ] 完成安全存储和数据库的最小闭环。
- [ ] 完成文件选择、下载、打开和分享的最小闭环。
- [ ] 明确后台传输是否作为首版硬性要求。
- [ ] 准备专用 OHOS 构建 runner 和签名材料。
- [ ] 明确哪些能力可以选择性降级。

Gate A（基础编译与登录）不通过时，不应直接进入大规模 UI/业务搬运；先解决 SDK、WebView、存储或权限问题。

Gate B（文件闭环）不通过时，不应承诺完整网盘功能；先确定沙箱下载或用户目录授权的降级方案。

Gate C（后台与发布）不通过时，可以发布“前台传输版本”，但不能对外承诺 Android 等价的后台传输体验。

## 14. 维护与长期收敛

建议先采用：

```text
main（共享源码）
  └── ohos（平台适配与 HAP 发布）
```

后续若满足以下条件，可以评估把 OHOS 平台层并入 main：

- Flutter OH SDK 和核心插件版本跟随稳定。
- Android、Windows、OHOS 可以使用同一组依赖来源。
- HAP 可以在单分支 CI 中稳定构建。
- 平台差异已全部收敛到独立适配器。

在此之前，长期保留 `ohos` 分支是合理的，但要把它当作“下游构建分支”，而不是“第二套产品”。

## 15. 参考资料

- [OH-Flutter Flutter SDK 与 Engine](https://gitcode.com/oh-flutter/flutter_flutter)
- [Flutter 3.47.7-ohos-1.0.0 ReleaseNote](https://gitcode.com/oh-flutter/flutter_flutter/blob/3.47.7-ohos-1.0.0/release-notes/Flutter%203.47.7-ohos%201.0.0%20ReleaseNote.md)
- [OpenHarmony Flutter 三方库适配总表](https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.md)
- [flutter_inappwebview OHOS 适配](https://gitcode.com/CPF-Flutter/flutter_inappwebview)
- [flutter_secure_storage OHOS 适配](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_secure_storage)
- [flutter_sqflite OHOS 适配](https://gitcode.com/CPF-Flutter/flutter_sqflite)
- [flutter_local_notifications OHOS 适配](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_local_notifications)
- [Flutter 官方支持平台](https://docs.flutter.dev/reference/supported-platforms)

