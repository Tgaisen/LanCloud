# LanCloud 平台适配交接

> 用途：新对话的唯一接力入口。先读本文件，再按仓库规则读取架构、基线和
> 兼容矩阵。纯 Dart 平台能力批次已经收口，不要从 Batch 1 重做。
>
> 更新时间：2026-11-21。

## 当前 Git 状态

- 仓库：`C:\Users\Potato\Desktop\LanCloud`
- 分支：`codex/platform-capabilities-batch1`
- 平台适配功能基线：`ff3ea87 fix(share): 按能力显示文件分享入口`
- 功能提交范围：`02c55c0..ff3ea87`，共 20 个提交
- 后续功能提交：
  - `5466324 fix(platform): 按能力选择目录与拖拽语义`
  - `094fee3 fix(platform): 按能力显示动态色与分享提示`
  - `153642a fix(notifications): 区分常驻进度与终态提醒`
  - `31d9eec fix(settings): 隐藏 Windows 进度通知入口`
  - `a59a1e3 refactor(platform): 收敛系统动作适配器`
- 开工前仍以 `git log -1` 和 `git status --short --branch` 为准
- 未 push、未创建 PR

最新全量基线：

- `tools\agent.cmd format`：369 files，0 changed
- `tools\agent.cmd analyze`：全量 0 issue
- `tools\agent.cmd test`：**1064 tests, all passed**，约 2 min 31 s
- 最近增量：系统动作 adapter，2 个测试文件、5 tests passed，约 1 s

当前规模与风险以 [BASELINE.md](./BASELINE.md) 为准，不在本文件重复维护。

## 已完成范围

Batch 1–7 的纯 Dart 范围已完成：

1. 不可变 `PlatformCapabilities`、`forPlatform()`、当前能力与 Riverpod
   provider，以及 Android/Windows/iOS/macOS/Linux/未知平台测试。
2. 设置页 Android 专属入口和网盘“从其他应用上传”按具体能力显示。
3. 扫码来源与分享收件箱按能力选择，iOS 不再进入缺通道路径。
4. 普通文件选择、另存为、默认下载目录和传输 SAF 路由已分流。
5. edge-to-edge、前台任务、本地通知初始化与设置入口按能力门控。
6. 系统分享、系统设置和更新交付收敛到窄接口或 adapter。

Batch 8–10 及通知设置收口也已完成：

- 缓存清理按私有临时目录与 SAF 能力选择。
- 设备信息的直接 `Platform.is*` 收口到 `PlatformSupport`。
- WebView 登录 UA 改用 `usesMobileWebUserAgent`。
- 动态色按 `DynamicColorSource` 探测，实际可用性继续运行时判断。
- 滚动条和菜单改为鼠标运行时信号，栏标题改为实际宽度。
- 文件分享入口区分原生分享、桌面定位和 unsupported 三种语义。
- 下载目录使用 `supportsSafDirectory`，窗口拖拽使用 `supportsDesktopDrop`。
- 动态色文案使用 `DynamicColorSource`；Cookie 导出消费分享 gateway 结果。
- 通知拆分 `supportsLocalNotifications` 与
  `supportsPersistentProgressNotifications`。
- Windows 隐藏进度通知设置，只保留完成/失败与收藏更新提醒。
- 外部链接和系统文件动作收敛到可注入 `ExternalLinkGateway` /
  `SystemOpenAdapter`。

## 当前能力快照

`PlatformCapabilities` 只描述当前 Dart 代码能否安全执行，不提前承诺插件或
操作系统理论上支持的功能。

- Android：除桌面拖拽外，建议覆盖的相机、文档提供器、分享接收、前台任务、
  本地通知、系统分享/保存、SAF、Android 设置入口、移动临时目录和移动 UA
  均为 true；动态色来源为壁纸，更新产物为 APK。
- Windows：本地通知、系统另存为和桌面拖拽为 true；常驻进度通知、相机、分享
  接收、前台任务、SAF、Android 设置入口和系统分享面板为 false；动态色来源
  为系统强调色，更新产物为 portable ZIP。
- iOS：只有系统另存为、私有移动临时目录和移动 UA 为 true；相机、分享接收、
  前台任务、本地通知、edge-to-edge、系统分享和系统设置入口为 false；
  动态色来源与更新产物为 none。文件选择/保存路径仍需构建和真机验收。
- macOS/Linux：只记录保守形态，可选能力关闭；仓库没有对应平台工程。
- 未知 `TargetPlatform`：所有可选能力关闭。

通知权限、生物识别硬件、动态色实际可用性属于运行时探测，不进入静态能力对象。

## 剩余平台分支

当前 `lib/` 中仍有 **11 个 Dart 文件、19 处**
`PlatformSupport` 分支 getter：

- `isDesktop` 4
- `isWindows` 10
- `isAndroid` 5
- `isMobile` 0
- 直接 `Platform.is*` 分支 0

复核命令：

```powershell
rg -n "PlatformSupport\.(isMobile|isDesktop|isAndroid|isWindows)" lib
rg -n "Platform\.is(Android|iOS|Windows|macOS|Linux)" lib
```

| 文件 | 引用 | 当前含义 | 建议 |
| --- | ---: | --- | --- |
| `lib/app.dart` | 2 | Windows 鼠标侧键、中文兜底字体 | 保留为 Windows 专属实现 |
| `lib/core/data/app_db.dart` | 1 | 桌面 sqflite FFI 初始化 | 保留为数据库实现选择 |
| `lib/core/device_info.dart` | 5 | Android/Windows/桌面系统信息数据源 | 保留，或后续单独做设备信息适配器 |
| `lib/core/external_link.dart` | 1 | factory 选择 Custom Tabs gateway | 保留在 adapter 内部 |
| `lib/core/file_picker_channel.dart` | 1 | 桌面禁止进入拍照原生通道 | 保留为底层 defensive guard |
| `lib/core/notifications.dart` | 2 | Windows AUMID 与通知图标配置 | 保留在通知平台实现内部 |
| `lib/core/saf_storage.dart` | 1 | Android SAF 通道保护 | 保留 |
| `lib/core/shared_downloads_storage.dart` | 1 | Android 公共 Downloads 通道保护 | 保留 |
| `lib/core/system_open.dart` | 3 | factory 选择 Android/iOS/桌面 adapter | 保留在 adapter 内部 |
| `lib/core/window_frame.dart` | 1 | Windows DWM 边框 | 保留 |
| `lib/ui/settings_page.dart` | 1 | Windows 通知注册表清理项 | 保留，属于 Windows 数据清理实现 |

目标不是把 19 处机械清零。低层通道实现和平台专属配置留在窄适配器内部，
通常比塞进能力对象更清楚。

## 后续工作

Batch 8A、8B、9、10 与 Batch 11 文档收口均已完成，没有剩余的常规纯 Dart
能力迁移批次。

- 新增平台时，先按能力矩阵和现有 adapter/gateway 接线，不要逐项搜
  `isAndroid` / `isDesktop` 后机械替换。
- 只有设备信息、深链收件或某个保留例外出现真实产品需求时，才拆成新的
  单模块批次；修改前仍执行 5 文件上限和跨层确认规则。
- iOS 自定义通道、Share Extension、Darwin 通知、真机构建验收，以及 HarmonyOS
  原生工程都属于后续原生适配，不属于本 Dart 路线。

## 必须保留的边界

- `PlatformSupport` 不删除；Android SDK、ABI、Hybrid Composition 和低层平台判断
  继续保留。
- `PlatformCapabilities` 只放不可变静态能力，不放 MethodChannel、插件调用或
  巨大 adapter API。
- 通知权限、生物识别硬件、动态色实际可用性继续运行时探测。
- 没有 `ohos/` 工程，不创建目录，不伪造 `TargetPlatform.ohos`。
- 没有 `macos/`、`linux/` 工程，不创建平台目录。
- iOS 能力保持 fail closed；完成 Swift、Info.plist、分享扩展、深链、通知和真机
  验收后再翻转相应值。

## 每批交付规则

开始前必须完整读取：

1. `AGENTS.md`
2. 本文件
3. `docs/ARCHITECTURE.md`
4. `docs/BASELINE.md`
5. `docs/PLATFORM_COMPATIBILITY.md`
6. `docs/DART_PLATFORM_ADAPTER_ROADMAP.md`
7. 本批涉及的代码和现有测试

跨 `core × ui` 的批次，修改前先给出：

- 文件清单
- Android/Windows/iOS 行为变化
- 测试方案
- 风险与保留例外

等待用户明确确认后再动手。完成后原样运行：

```powershell
tools\agent.cmd format
tools\agent.cmd analyze
tools\agent.cmd test
```

不要追加参数、管道或重定向。若测试总数变化，同步 `docs/BASELINE.md`；
逐批历史追加到 `docs/BASELINE_HISTORY.md`。

不新增依赖，不改版本号、原生工程或 l10n 生成文件。不要自行 commit，
除非用户明确说“提交”；禁止自行 push 或创建 PR。

## 新对话接力 Prompt

```text
继续 LanCloud 的 Flutter/Dart 平台适配工作。

仓库：
C:\Users\Potato\Desktop\LanCloud

分支：
codex/platform-capabilities-batch1

PlatformCapabilities、原路线 Batch 1–7、Batch 8A/8B/9/10 和文档收口均已完成。
当前全量基线为 1064 tests passed。不要重做已完成批次。

开始前必须完整读取：
1. AGENTS.md
2. docs/PLATFORM_ADAPTER_HANDOFF.md
3. docs/ARCHITECTURE.md
4. docs/BASELINE.md
5. docs/PLATFORM_COMPATIBILITY.md
6. docs/DART_PLATFORM_ADAPTER_ROADMAP.md
7. 本批涉及的代码和测试

先核对 git status、分支和 HEAD，并重新统计：
rg -n "PlatformSupport\.(isMobile|isDesktop|isAndroid|isWindows)" lib
rg -n "Platform\.is(Android|iOS|Windows|macOS|Linux)" lib

当前预期为 11 个 Dart 文件、19 处分支 getter：isDesktop 4、isWindows 10、
isAndroid 5、isMobile 0；直接 Platform.is* 为 0。这些是已确认的低层实现、
平台专属配置或 adapter factory 例外，不要为了清零而机械能力化。

先确认实际需求；若确实需要新增能力或拆 adapter，单批最多 5 个文件。跨
core × ui 时，修改前先给文件清单、Android/Windows/iOS 行为变化、测试方案和
遗留风险，等待明确确认后再修改。

完成后必须原样运行：
tools\agent.cmd format
tools\agent.cmd analyze
tools\agent.cmd test

不新增依赖，不改版本号、原生工程或 l10n 生成文件。不要自行 push 或创建 PR；
只有我明确说“提交”时才 commit。
```
