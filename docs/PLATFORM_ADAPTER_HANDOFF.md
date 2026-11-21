# LanCloud 平台适配交接

> 用途：新对话的唯一接力入口。先读本文件，再按仓库规则读取架构、基线、
> 兼容矩阵和本轮涉及的代码，不要从 Batch 1 重做。
>
> 更新时间：2026-11-21。

## 当前 Git 状态

- 仓库：`C:\Users\Potato\Desktop\LanCloud`
- 分支：`codex/platform-capabilities-batch1`
- 平台适配功能基线：`ff3ea87 fix(share): 按能力显示文件分享入口`
- 功能提交范围：`02c55c0..ff3ea87`，共 20 个提交
- 本交接文档提交位于 `ff3ea87` 之后；开工前以 `git log -1` 和
  `git status --short --branch` 为准
- 未 push、未创建 PR

最新全量基线：

- `tools\agent.cmd format`：369 files，0 changed
- `tools\agent.cmd analyze`：全量 0 issue
- `tools\agent.cmd test`：**1061 tests, all passed**，约 2 min 17 s
- 最近增量：6 个测试文件、86 tests passed，约 51 s

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

后续纯 Dart 小批还完成了：

- 缓存清理按私有临时目录与 SAF 能力选择。
- 设备信息的直接 `Platform.is*` 收口到 `PlatformSupport`。
- WebView 登录 UA 改用 `usesMobileWebUserAgent`。
- 动态色按 `DynamicColorSource` 探测，实际可用性继续运行时判断。
- 滚动条和菜单改为鼠标运行时信号，栏标题改为实际宽度。
- 文件分享入口区分原生分享、桌面定位和 unsupported 三种语义。

## 当前能力快照

`PlatformCapabilities` 只描述当前 Dart 代码能否安全执行，不提前承诺插件或
操作系统理论上支持的功能。

- Android：除桌面拖拽外，建议覆盖的相机、文档提供器、分享接收、前台任务、
  本地通知、系统分享/保存、SAF、Android 设置入口、移动临时目录和移动 UA
  均为 true；动态色来源为壁纸，更新产物为 APK。
- Windows：本地通知、系统另存为和桌面拖拽为 true；相机、分享接收、前台任务、
  SAF、Android 设置入口和系统分享面板为 false；动态色来源为系统强调色，
  更新产物为 portable ZIP。
- iOS：只有系统另存为、私有移动临时目录和移动 UA 为 true；相机、分享接收、
  前台任务、本地通知、edge-to-edge、系统分享和系统设置入口为 false；
  动态色来源与更新产物为 none。文件选择/保存路径仍需构建和真机验收。
- macOS/Linux：只记录保守形态，可选能力关闭；仓库没有对应平台工程。
- 未知 `TargetPlatform`：所有可选能力关闭。

通知权限、生物识别硬件、动态色实际可用性属于运行时探测，不进入静态能力对象。

## 剩余平台分支

截至功能提交 `ff3ea87`，`lib/` 中仍有 **15 个 Dart 文件、28 处**
`PlatformSupport` 分支 getter：

- `isDesktop` 9
- `isWindows` 13
- `isAndroid` 6
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
| `lib/core/external_link.dart` | 1 | Android Custom Tabs 与普通浏览器回退 | 候选：系统动作 gateway |
| `lib/core/file_picker_channel.dart` | 1 | 桌面禁止进入拍照原生通道 | 保留为底层 defensive guard |
| `lib/core/notifications.dart` | 5 | Windows AUMID/图标、桌面无常驻进度 | 候选：通知形态与权限配置拆分 |
| `lib/core/saf_storage.dart` | 1 | Android SAF 通道保护 | 保留 |
| `lib/core/shared_downloads_storage.dart` | 1 | Android 公共 Downloads 通道保护 | 保留 |
| `lib/core/system_open.dart` | 4 | Android 文件打开、桌面 shell、资源管理器 | 候选：系统动作 gateway |
| `lib/core/window_frame.dart` | 1 | Windows DWM 边框 | 保留 |
| `lib/ui/cookie_sheet.dart` | 1 | 桌面复制后提示 | 候选：消费分享 gateway 结果或平台形态 |
| `lib/ui/desktop_drop_target.dart` | 1 | 是否包桌面拖拽目标 | 候选：改为 `supportsDesktopDrop` |
| `lib/ui/download_directory_settings_tile.dart` | 1 | 是否显示 Android SAF 目录 | 候选：改为 `supportsSafDirectory` |
| `lib/ui/settings_page.dart` | 1 | Windows 通知注册表清理项 | 保留，除非新增独立产品能力字段 |
| `lib/ui/theme_settings_tile.dart` | 2 | Windows 动态色文案 | 候选：改为 `DynamicColorSource` |

目标不是把 28 处机械清零。低层通道实现和平台专属 UI 留在窄适配器内部，
通常比塞进能力对象更清楚。

## 推荐后续批次

保守估计还需要 **4–6 个批次**；如果决定拆分深链收件和完整设备信息，取上限。
每批仍控制在 5 个文件以内，且一次只改一个模块。

### Batch 8A：目录与拖拽语义

候选文件（含测试，最多 5 个）：

- `lib/ui/download_directory_settings_tile.dart`
- `lib/ui/desktop_drop_target.dart`
- 对应 UI/provider 测试

重点：分别用 `supportsSafDirectory` 和 `supportsDesktopDrop` 替换能明确表达的
平台判断，同时保留 Android SAF 通道和桌面拖放实现本身。

### Batch 8B：动态色与分享提示

候选文件（含测试，最多 5 个）：

- `lib/ui/theme_settings_tile.dart`
- `lib/ui/cookie_sheet.dart`
- 对应测试

重点：动态色文案跟随 `DynamicColorSource`；Cookie 提示优先消费现有分享
gateway 的结果或明确形态，不再单独猜测桌面端。若需要新增能力字段，先说明
已有字段为何不足。

### Batch 9：通知边界

候选文件：

- `lib/core/notifications.dart`
- `test/notifications_*` 或现有通知能力测试
- 如确有必要，只增加已消费的通知形态字段和
  `test/platform_capabilities_test.dart`

重点是把“能否初始化通知”“是否有常驻进度”和 Windows AUMID/图标写入分开。
通知权限仍是运行时查询；不要把所有 Windows 注册表代码搬进能力对象。

### Batch 10：系统动作边界

候选文件：

- `lib/core/external_link.dart`
- `lib/core/system_open.dart`
- 对应 gateway/UI 测试

重点：保持 Android Custom Tabs、iOS `open_filex`、Windows 资源管理器行为不变，
把系统动作选择放到可注入 adapter；不要新增原生通道。

### Batch 11：最终例外清单与验收

候选文件：

- 本文
- [DART_PLATFORM_ADAPTER_ROADMAP.md](./DART_PLATFORM_ADAPTER_ROADMAP.md)
- [PLATFORM_COMPATIBILITY.md](./PLATFORM_COMPATIBILITY.md)
- 必要时 `docs/ARCHITECTURE.md`、`docs/BASELINE.md` / `BASELINE_HISTORY.md`

逐项确认剩余引用是低层实现、输入形态还是产品能力，并记录“保留原因”。
若没有代码/测试变化，只需核对统计和文档；不要为清零而扩大范围。

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

上一轮已完成 PlatformCapabilities、原路线 Batch 1–7 及后续纯 Dart 小批。
平台适配功能基线是 ff3ea87；其后只增加了交接文档。全量基线为 1061 tests
passed。不要重做已完成批次。

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

当前预期为 15 个 Dart 文件、28 处分支 getter：isDesktop 9、isWindows 13、
isAndroid 6、isMobile 0；直接 Platform.is* 为 0。不要为了清零引用而机械
能力化。低层通道、SAF、窗口、数据库和设备信息实现应优先保留。

从 docs/PLATFORM_ADAPTER_HANDOFF.md 的 Batch 8A 开始。若该批实际跨
core × ui，修改前先给文件清单、Android/Windows/iOS 行为变化、测试方案和遗留风险，
等待我明确确认后再修改。单批最多 5 个文件。

完成后必须原样运行：
tools\agent.cmd format
tools\agent.cmd analyze
tools\agent.cmd test

不新增依赖，不改版本号、原生工程或 l10n 生成文件。不要自行 push 或创建 PR；
只有我明确说“提交”时才 commit。
```
