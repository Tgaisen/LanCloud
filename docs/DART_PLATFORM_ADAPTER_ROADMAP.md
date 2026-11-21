# Flutter/Dart 平台能力适配改造清单

> 文档状态：平台能力审查、实施路线与当前完成快照。Batch 1–7 的纯 Dart
> 范围已实施；仍需原生工程或人工验收的项目在下文单独列出。
>
> 核验日期：2026-11-21。
>
> 范围：只讨论 Flutter/Dart 层可完成的改造，不新增依赖、不改原生工程、
> 不把“未来可能支持”提前写成“当前已支持”。

本文配合 [PLATFORM_COMPATIBILITY.md](./PLATFORM_COMPATIBILITY.md) 使用：
前者说明各平台现在有什么，本文说明哪些 Dart 侧结构适合先改、怎么拆、先改什么。

## 实施状态（2026-11-21）

| 批次 | 状态 | 当前结果 |
| --- | --- | --- |
| Batch 1 | ✅ 完成 | 新增不可变 `PlatformCapabilities`、平台矩阵、Riverpod provider 与纯 Dart 测试 |
| Batch 2 | ✅ 完成 | 设置页 Android 专属入口、网盘“从其他应用上传”改按具体能力显示 |
| Batch 3 | ✅ 完成 | 二维码来源和分享收件箱按能力选择；iOS 不再进入缺通道路径 |
| Batch 4 | ✅ 完成 | 普通文件选择与另存为在 Android/其他平台分别路由；iOS 使用 `file_picker` |
| Batch 5 | ✅ 完成 | 默认下载目录与传输 SAF 路由收口；iOS 不再调用 external storage |
| Batch 6 | ✅ 完成 | edge-to-edge 与前台任务仅在能力支持时初始化 |
| Batch 7 | ✅ 完成 | 新增系统分享、系统设置、更新交付和本地通知窄接口；通知设置入口按能力显示 |

当前仍有 24 个 Dart 文件引用 `PlatformSupport` 的分支 getter，共 42 处：
`isDesktop` 19 处、`isWindows` 12 处、`isAndroid` 8 处、`isMobile` 3 处。
其中多数是布局/输入偏好或低层实现选择，不再直接等于产品能力。
`core/device_info.dart` 仍直接使用 5 处 `dart:io Platform.is*`，留给独立清理。

本阶段未新增依赖、未修改 Android/Windows/iOS 原生工程，也未改变版本号。
iOS 的普通文件选择、保存和下载目录虽然已有共享 Dart 路径，但仍需构建和真机验收。

## 1. 结论

当前仓库已经有 35 个 Dart 文件引用 `PlatformSupport`，共约 71 处引用；其中
`isMobile` 有 13 处、分布在 9 个文件，`isDesktop` 有 24 处。数量本身不是问题，
问题在于同一个判断经常同时表达不同含义：

- 系统形态：手机或桌面。
- 输入方式：触摸或鼠标。
- 静态能力：当前构建是否真的有相机、分享、保存、前台服务。
- 运行时状态：权限、硬件、系统主题色是否可用。
- 实现选择：调用 Android 通道、`file_picker`、FFI 或系统 shell。

最值得先做的不是给每个平台写一套 UI，而是增加一份**可测试、可注入、与当前
实现一致的平台能力描述**，再把 `isMobile`、部分 `isDesktop` 和直接平台分支
迁移到具体语义。

不依赖原生工作的首批改造包括：

1. 新增 `PlatformCapabilities` 和纯 Dart 平台矩阵测试。
2. 修复设置页用 `!isMobile` 过滤 Android 专用入口的问题。
3. 让“从其他应用上传”和“拍照扫码”按真实能力显示。
4. 让非 Android 平台的普通文件选择、另存为走现有的 `file_picker`。
5. 修正非 Android 默认下载目录解析，不再调用 iOS 不支持的 external storage。
6. 把启动时的 edge-to-edge、前台任务、分享收件箱分别按能力初始化。
7. 把系统分享、权限、通知和更新先收敛到窄接口，行为保持现状。

上述工作不需要新增 `pubspec.yaml` 依赖，也不需要碰 Android Kotlin、Windows
C++ 或 iOS Swift。

## 2. 先区分四种概念

| 概念 | 用途 | 当前例子 | 建议归属 |
| --- | --- | --- | --- |
| 平台形态 | 决定大屏/小屏、触摸/鼠标等交互偏好 | `isDesktop`、`isMobile` | 保留少量形态判断，或改为指针/宽度判断 |
| 静态能力 | UI 是否显示入口、选择哪条实现 | 相机、分享接收、系统保存、前台服务 | `PlatformCapabilities` |
| 运行时探测 | 设备当前是否真的可用 | 生物识别、动态取色、通知权限 | 对应服务内部探测 |
| 行为适配器 | 执行具体系统动作 | SAF、公共 Downloads、前台任务后端 | 窄 interface / gateway / port |

如果一个值会随硬件、权限或系统设置变化，就不应写进静态平台矩阵；例如“设备有
生物识别硬件”不能等同于 `isAndroid == true`。反过来，如果当前 iOS 还没有
Swift 实现，也不能因为插件在 pub.dev 声明支持 iOS，就把静态能力提前标成 `true`。

## 3. 当前能力模型

当前实现使用一个不可变能力对象，并允许 Riverpod 测试覆盖。只加入已经实际
影响 UI、启动或实现选择的字段，没有提前做几十个布尔值。

```dart
enum PlatformFormFactor { mobile, desktop, unknown }

enum PlatformInputStyle { touchFirst, pointerFirst, unknown }

enum DynamicColorSource { none, wallpaper, systemAccent }

enum UpdateArtifact { none, androidApk, windowsPortable }

@immutable
final class PlatformCapabilities {
  const PlatformCapabilities({
    required this.formFactor,
    required this.inputStyle,
    required this.supportsCameraCapture,
    required this.supportsDocumentProviderUpload,
    required this.supportsIncomingShare,
    required this.supportsForegroundTask,
    required this.supportsLocalNotifications,
    required this.supportsEdgeToEdgeSystemUi,
    required this.supportsSystemShare,
    required this.supportsSystemFileSave,
    required this.supportsSafDirectory,
    required this.supportsPermissionManagement,
    required this.supportsDefaultLinkSettings,
    required this.supportsAppSettingsPage,
    required this.supportsDesktopDrop,
    required this.usesPrivateMobileTemporaryDirectory,
    required this.usesMobileWebUserAgent,
    required this.dynamicColorSource,
    required this.updateArtifact,
  });

  // 省略字段声明和 forPlatform() 工厂；字段含义必须有代码消费者。
}

final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (_) => PlatformCapabilities.current,
);
```

建议文件：

- `lib/core/platform_capabilities.dart`
- `test/platform_capabilities_test.dart`

`PlatformSupport` 继续保留 Android SDK、ABI 和 WebView 合成方式等低层探测或实现
细节，不要求把现有类删除。能力对象负责“产品是否提供”，`PlatformSupport` 负责
“系统 API 返回什么”。

建议的当前值如下。第一批只记录真实实现；例如 iOS 相机、分享和前台任务仍未
接入，就不因为这些系统理论上支持而标为可用。

| 能力 | Android | Windows | iOS |
| --- | --- | --- | --- |
| 系统形态 | mobile | desktop | mobile |
| 相机拍照 | true | false | false |
| 从其他应用选择文件 | true | false | false |
| 系统分享 | true | false；当前是复制/定位降级 | false |
| 系统另存为 | true | true | false；可优先通过 Dart 改走 `file_picker` |
| 接收其他应用分享 | true | false | false |
| 前台任务 | true | false | false |
| Android 权限/默认链接设置 | true | false | false |
| 桌面拖拽 | false | true | false |
| 私有临时目录可整体清理 | true | false | true |
| 使用移动网页 UA | true | false | true |
| 动态色来源 | 壁纸/系统色 | 系统强调色 | 无 |
| 更新产物 | Android APK | Windows portable ZIP | 无 |

当某平台补齐原生实现后，只修改能力矩阵并增加测试，不需要继续在页面里寻找
`isMobile`。

## 4. `isMobile` 逐项拆分

当前 13 处 `isMobile` 不应统一替换成同一个新布尔值。建议按下表拆分：

| 位置 | 当前含义 | 建议语义 |
| --- | --- | --- |
| `lib/main.dart` 系统栏初始化 | Android/iOS 都算移动端 | `supportsEdgeToEdgeSystemUi`，当前仅 Android |
| `lib/main.dart` 前台任务初始化 | 插件声明支持 Android/iOS | `supportsForegroundTask`，当前仅 Android 配置完整 |
| `lib/core/app_cache.dart` 整体清缓存 | 移动临时目录为应用私有 | `usesPrivateMobileTemporaryDirectory` |
| `lib/ui/common.dart` 自适应菜单使用底部弹层 | 触摸优先 | 使用 `PointerSupport.hasMouse` + 宽度，不按 OS |
| `lib/ui/drive_page.dart` “从其他应用上传” | Android 文档提供器通道 | `supportsDocumentProviderUpload` |
| `lib/core/download_path_service.dart` 移动目录 | Android 外部存储与 iOS 下载目录不同 | 明确区分 Android 路径与通用移动目录 |
| `lib/core/foreground_task_coordinator.dart` 三次启动/更新/停止 | 平台是否有可用后台后端 | `supportsForegroundTask` |
| `lib/ui/settings_page.dart` 隐藏 Android 专用入口 | 当前判断写反了语义 | 分别使用权限、默认链接、应用设置能力 |
| `lib/core/share_inbox.dart` 初始/运行中分享 | 当前只有 Android 入口完整 | `supportsIncomingShare` |
| `lib/ui/web_login_page.dart` WebView UA | 移动网页适配策略 | `usesMobileWebUserAgent`，不是能力 |

其中优先级最高的是 `settings_page.dart`：现在的条件
`!PlatformSupport.isMobile && _androidOnlyEntries.contains(...)` 会让桌面端
隐藏入口，但 iOS 仍显示“管理权限”等 Android 专用项。先分别改为
`supportsPermissionManagement`、`supportsDefaultLinkSettings` 和
`supportsAppSettingsPage` 即可修复，不必等待完整适配器迁移。

当前 24 处 `isDesktop` 可分为四类，不能按同一种方式迁移：

| 类别 | 典型位置 | 建议 |
| --- | --- | --- |
| 输入/布局偏好 | `ui/app_scroll.dart`、收藏和传输页的紧凑标题 | 保留形态判断，逐步改为指针与宽度判断 |
| 静态系统能力 | `download_mark.dart`、`transfers_page.dart`、`system_share.dart` | 改为具体分享/定位能力 |
| 实现选择 | `file_picker_channel.dart`、`system_file_saver.dart`、`data/app_db.dart` | 下沉到文件或数据库适配器 |
| 平台专属实现 | `notifications.dart`、`window_frame.dart` | 留在通知或窗口适配器内部 |

`lib/core/device_info.dart` 是当前 `lib/core` 中仍直接使用
`dart:io Platform.isWindows/isMacOS/isLinux` 的文件，与“平台判断集中在
`PlatformSupport`”的约定不完全一致。它适合作为低风险的后续清理项，不需要改动
设备信息展示协议。

## 5. 现在就能做的 Dart 改造

### 5.1 P0：低风险，先做

| 项目 | 当前文件 | 改造内容 | 风险/验证 |
| --- | --- | --- | --- |
| 平台能力矩阵 | 新增 `core/platform_capabilities.dart` | 纯数据对象 + `forPlatform()` + provider | 无行为变化；测试 Android/Windows/iOS |
| 设置入口过滤 | `ui/settings_page.dart` | 用具体能力替换 `!isMobile` | 增加 iOS 隐藏入口回归测试 |
| 上传入口显示 | `ui/drive_page.dart` | 只有文档提供器通道可用时才显示“从其他应用上传” | Windows 保持无入口，iOS 不再显示失败入口 |
| 扫码来源 | `ui/qr_scan.dart` | `hasCameraCapture` 改为能力；无相机时直接选图片 | 现有 Windows 测试扩展 iOS |
| 分享收件箱 | `core/share_inbox.dart` | 只在 `supportsIncomingShare` 时初始化/监听 | 避免 iOS 无扩展时注册无效监听 |
| 普通文件选择 | `core/file_picker_channel.dart` | `pickFiles` 改成“Android 自定义通道，其他平台 `file_picker`” | 现有 `file_picker` 已声明 iOS 支持 |
| 另存为 | `core/system_file_saver.dart` | Android 保留 `ACTION_CREATE_DOCUMENT`，非 Android 统一走 `file_picker.saveFile` | 去掉 `_saveOnDesktop` 的平台误导；iOS 可先获得 Dart 路径 |
| 下载目录 | `core/download_path_service.dart` | Android 走公共 Downloads/外部存储；其他平台优先 `getDownloadsDirectory()` | `path_provider` 声明 iOS Downloads 可用 |
| 启动能力 | `main.dart`、`foreground_task_coordinator.dart` | 分别判断系统栏、前台任务、分享收件箱 | 不影响 Windows 生命周期语义 |

### 5.2 P1：仍需纯 Dart，但需要接口拆分

| 项目 | 建议接口 | 为什么现在适合 |
| --- | --- | --- |
| 系统分享 | `SystemShareGateway` | 现有 `SystemShare` 已是单文件入口，可保持 Windows 降级为独立实现 |
| 权限设置 | `SystemSettingsGateway` | 已有 `AppPermissions.instance` 测试注入模式，可改成正式接口 |
| 前台任务 | `ForegroundTaskBackend` + no-op 实现 | 接口已存在，只需在组合根按能力选择后端 |
| 通知 | `NotificationCapability` / sink | 现有传输通知和收藏通知已经通过窄 sink 注入 |
| 更新 | `UpdateDeliveryAdapter` | `updateSupportedProvider` 和 `downloadUrl()` 已集中，适合抽制品类型 |
| 分享收件箱/深链 | `IncomingContentGateway` | 两个单例都在启动时初始化，可在不改原生的前提下先隔离生命周期 |
| 文件服务 | `FileSelectionGateway` / `FileSaveGateway` | `SharedDownloadsGateway` 已证明这种窄接口模式适合项目 |
| 设备信息平台判断 | `DeviceInfo` 适配器或 `PlatformSupport` 语义 getter | 当前只有一个文件直接使用 `dart:io Platform.is*`，可独立清理 |

这些改造先保持 Android/Windows 行为不变，只把平台判断从页面搬到组合层。

## 6. 推荐实施批次

以下批次都按“单次改动一个模块、尽量不超过 5 个文件”拆分。

### Batch 1：能力矩阵，不改变行为

文件：

- `lib/core/platform_capabilities.dart`
- `test/platform_capabilities_test.dart`

验收：

- Android/Windows/iOS 的纯矩阵测试全部通过。
- 所有未知平台默认不启用可选能力。
- 不修改现有页面和启动流程。

### Batch 2：先修 UI 的错误隐藏条件

文件：

- `lib/ui/settings_page.dart`
- `lib/ui/drive_page.dart`
- `test/permissions_settings_test.dart`
- 一个驱动“从其他应用上传”菜单能力的组件测试

验收：

- Android 行为不变。
- Windows 继续隐藏 Android 设置和文档提供器入口。
- iOS override 下不再显示不可用入口。

### Batch 3：扫码与分享收件箱

文件：

- `lib/ui/qr_scan.dart`
- `lib/core/share_inbox.dart`
- `test/qr_dialog_test.dart`
- 新增 `test/share_inbox_capability_test.dart`

验收：

- 有相机的平台才显示“拍照”。
- 无相机平台直接进入图库/文件选择。
- 分享扩展未接入的 iOS 不注册无效监听。

### Batch 4：文件选择与另存为

文件：

- `lib/core/file_picker_channel.dart`
- `lib/core/system_file_saver.dart`
- 新增或更新文件选择/保存测试
- 如需要，新增一个可注入的 channel 测试辅助

验收：

- Android 仍走 `lancloud/file_picker`。
- Windows 行为不变。
- 非 Android 保存不再无条件调用 Android 通道。
- 用户取消时仍返回 `null`，不引入空字符串歧义。

### Batch 5：默认下载目录与传输端口

文件：

- `lib/core/download_path_service.dart`
- `lib/core/transfer/transfer_download_port.dart`
- `test/shared_downloads_gateway_test.dart`
- `test/download_target_test.dart`

验收：

- Android 公共 Downloads/SAF/固定路径优先级不变。
- 非 Android 不再调用 external storage。
- `targetMode()` 用静态的 `supportsSafDirectory` 选择 SAF 路径，同时继续通过
  `SharedDownloadsGateway.isSupported()` 查询 Android 版本相关的运行时能力。
- 传输模块改动必须同步更新测试，符合 AGENTS.md 的 DoD。

### Batch 6：启动与前台任务

文件：

- `lib/main.dart`
- `lib/core/foreground_task_coordinator.dart`
- 能力矩阵测试
- 前台任务或启动组合测试

验收：

- Android 系统栏和前台服务行为不变。
- Windows 不初始化移动端服务。
- iOS 在 Info.plist 未完成前不启动不可用的后台任务。
- 目前“应用启动/回前台补检”的产品语义不变。

### Batch 7：分享、权限、更新与通知的适配器

每一类单独提交，不要把它们和前面的 UI 修复混在一起：

- `SystemShareGateway`：Android native、桌面降级、unsupported 三种实现。
- `SystemSettingsGateway`：Android 权限/默认链接页；其他平台不提供入口。
- `UpdateDeliveryAdapter`：Android APK、Windows ZIP、无产物。
- `NotificationService`：能力标志只决定是否请求、显示或隐藏相关设置；实际权限
  仍在运行时查询。

## 7. 不建议现在重写的部分

- 不要为了统一风格把所有 `isDesktop` 都换成业务能力。`app.dart` 的字体兜底、
  `window_frame.dart` 的 DWM 逻辑、`data/app_db.dart` 的 FFI 选择属于实现细节，
  留在对应平台/存储适配器中更清楚。
- 不要把 `isDesktop` 驱动的滚动条、紧凑区块标题立即替换成能力布尔值。它们更
  接近输入方式和布局策略，建议后续统一用 `PointerSupport.hasMouse`、宽度和
  `MediaQuery` 判断。
- 不要在 `PlatformCapabilities` 里加入“iOS 应该支持分享”这种未来承诺；值是
  当前代码能否安全执行。
- 不要新增一个包含所有平台 SDK 调用的巨大 `PlatformAdapter`。项目已经采用
  `SharedDownloadsGateway`、`ForegroundTaskBackend` 等窄接口，这个方向更稳。
- 不要在没有 `macos/` 或 `ohos/` 工程时创建平台目录，也不要为它们提前加
  `TargetPlatform.ohos`/不可用插件分支。

## 8. 原生工作边界

以下即使能在 Dart 里先加接口，也不能靠纯 Dart 变成可用功能：

- iOS 自定义 `lancloud/file_picker`、`lancloud/share`、`lancloud/links`。
- iOS Share Extension、App Group、Universal Links。
- iOS 的 `UIBackgroundModes`、Darwin 通知初始化和 Face ID 用途说明。
- HarmonyOS NEXT 的 `ohos/` 工程、HAP、文件/URI/通知/持续任务实现。
- 系统原生分享、后台服务和产品更新策略。

这些工作在完成原生实现后再翻转对应能力值，不能提前改 UI 为“支持”。

## 9. 测试与验收策略

### 9.1 纯能力矩阵

新增 `test/platform_capabilities_test.dart`，至少覆盖：

- Android、Windows、iOS、macOS、Linux 五个 `TargetPlatform` 的默认值。
- 未识别平台的 fail-closed 行为。
- `DynamicColorSource` 和 `UpdateArtifact` 的映射。
- 测试只读 immutable 对象，不依赖 MethodChannel。

### 9.2 UI 和组合层

- Widget 测试优先通过 `ProviderScope.overrides` 注入能力对象。
- 需要临时覆盖系统平台时使用 `debugDefaultTargetPlatformOverride`，并在
  `finally` 中还原；现有测试已采用这个模式。
- 新测试至少要覆盖 Android 不变、Windows 不变、iOS 不走缺通道分支。
- 对 `settings_page` 增加 iOS 入口隐藏回归；对 `qr_scan` 增加无相机路径测试。

### 9.3 每个批次的交付门禁

按 AGENTS.md 执行：

```powershell
tools\agent.cmd format
tools\agent.cmd analyze
tools\agent.cmd test
```

- `core/data/`、`core/transfer/`、`core/update/` 等目录有改动时必须带测试。
- 文档本身不改变用例数；如果实现批次改变测试总数，再同步 `docs/BASELINE.md`。
- 纯重构不能只靠“已编译”：至少验证 Android 默认路径、Windows 桌面路径和
  iOS unsupported/可用路径的测试结果。

## 10. 原推荐决策（已执行）

Batch 1–3 已按以下顺序完成，并继续完成 Batch 4–7 的纯 Dart 范围：

1. 先建立能力矩阵和测试基线。
2. 修复 iOS 设置入口、上传入口、扫码入口的错误展示。
3. 再处理文件选择/保存和下载路径这类现有 Dart 分支错误。
4. 最后再做分享、权限、通知、更新的端口化重构。

这样后续 iOS 或鸿蒙开发者只需要实现一个接口并翻转能力值，不需要逐个页面追踪
`isMobile` 和 `isDesktop`。

## 11. 代码入口

| 主题 | 代码 |
| --- | --- |
| 当前平台判断 | [`lib/core/platform_support.dart`](../lib/core/platform_support.dart) |
| 设置页过滤 | [`lib/ui/settings_page.dart`](../lib/ui/settings_page.dart) |
| 上传入口 | [`lib/ui/drive_page.dart`](../lib/ui/drive_page.dart) |
| 扫码 | [`lib/ui/qr_scan.dart`](../lib/ui/qr_scan.dart) |
| 文件选择/保存 | [`lib/core/file_picker_channel.dart`](../lib/core/file_picker_channel.dart)、[`lib/core/system_file_saver.dart`](../lib/core/system_file_saver.dart) |
| 默认下载目录 | [`lib/core/download_path_service.dart`](../lib/core/download_path_service.dart)、[`lib/core/transfer/transfer_download_port.dart`](../lib/core/transfer/transfer_download_port.dart) |
| 分享收件箱 | [`lib/core/share_inbox.dart`](../lib/core/share_inbox.dart)、[`lib/core/system_share.dart`](../lib/core/system_share.dart) |
| 前台任务 | [`lib/main.dart`](../lib/main.dart)、[`lib/core/foreground_task_coordinator.dart`](../lib/core/foreground_task_coordinator.dart) |
| 通知 | [`lib/core/notifications.dart`](../lib/core/notifications.dart) |
| 更新 | [`lib/core/update/update_service.dart`](../lib/core/update/update_service.dart) |
| 设备信息平台判断 | [`lib/core/device_info.dart`](../lib/core/device_info.dart) |
| 现有测试 | [`test/permissions_settings_test.dart`](../test/permissions_settings_test.dart)、[`test/qr_dialog_test.dart`](../test/qr_dialog_test.dart)、[`test/shared_downloads_gateway_test.dart`](../test/shared_downloads_gateway_test.dart)、[`test/update_service_test.dart`](../test/update_service_test.dart) |
