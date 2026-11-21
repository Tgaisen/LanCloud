# 平台功能与适配差异

> 文档状态：当前仓库实现快照，不是对未适配平台的功能承诺。
>
> 核验日期：2026-11-21。
>
> 产品范围：Android、Windows 为当前交付平台；HarmonyOS NEXT 尚未接入；
> iOS 仅保留平台目录；macOS 没有平台工程。

本文基于仓库中的 Dart 平台分支、Android/Windows/iOS 原生工程、插件注册、
CI 与发布脚本整理。**“已接入”表示代码和平台配置存在，不等于已完成对应系统的
逐项人工验收。** Android、Windows 的构建状态见
[BASELINE.md](./BASELINE.md)，功能级人工验收仍需另行记录。

Dart 侧可先实施的拆分、能力开关和分批改造计划见
[DART_PLATFORM_ADAPTER_ROADMAP.md](./DART_PLATFORM_ADAPTER_ROADMAP.md)。

## 1. 先说结论

- 业务、网络、模型、状态管理、本地化、备份格式和绝大部分 UI 都在共享 Dart
  代码中，新平台的主要工作是补齐系统能力，不是重写产品。
- Android 与 Windows 已经形成可构建、可发布的交付链。两者最大的差异集中在
  文件选择/保存、系统分享、深链、后台保活、通知和更新方式。
- HarmonyOS NEXT 当前没有 `ohos/` 工程，不能把“Dart 代码可复用”理解为
  “已经支持”。依赖替换、原生通道、HAP 签名和发布流程仍按
  [OHOS_ADAPTATION.md](./OHOS_ADAPTATION.md) 的草案执行。
- iOS 目录是 Flutter 平台壳，部署目标为 iOS 15；共享 UI 和多数插件路径可复用，
  但当前没有 Swift 自定义通道、分享扩展、深链声明、Darwin 通知初始化和发布
  链路，不能直接视为可用版本。
- macOS 没有 `macos/` 工程。`PlatformSupport.isDesktop` 虽然包含 macOS，
  只表示部分共享代码会走桌面分支，并不表示 macOS 已适配。
- 收藏自动检测、WebDAV 自动备份都只在应用启动或回到前台且到期时补做；进程被
  系统结束后不会定时唤醒。这一点与平台无关，后续平台不应承诺“后台常驻定时”。

## 2. 标记口径

| 标记 | 含义 |
| --- | --- |
| ✅ 已接入 | 有共享代码、平台实现/插件注册和对应配置；Android/Windows 继续以构建基线为准 |
| ◐ 待补齐 | 平台工程或插件能力存在，但缺少关键原生实现、权限配置、初始化或验收 |
| ○ 未实现 | 当前平台明确没有该能力，或已有目标但代码路径不成立 |
| — 未适配 | 没有平台工程或不在当前产品范围；共享代码可能仍可复用 |
| N/A | 该系统不存在对应概念，或桌面进程模型使该能力不适用 |

“未知”只用于确实无法从仓库判断的外部行为。当前仓库中，鸿蒙、iOS、macOS
的大多数答案可以由“是否已有平台实现”直接判断，因此本文不再用“未知”代替
“未适配”或“待补齐”。

## 3. 当前平台基线

| 项目 | Android | Windows | HarmonyOS NEXT | iOS | macOS |
| --- | --- | --- | --- | --- | --- |
| 当前产品支持 | ✅ 是 | ✅ 是 | — 否，技术验证暂缓 | — 否，仅保留目录 | — 否 |
| 平台工程 | ✅ `android/` | ✅ `windows/` | — 无 `ohos/` | ◐ `ios/` Flutter 壳 | — 无 `macos/` |
| 构建与发布 CI | ✅ APK 构建/发布 | ✅ x64 便携版构建/发布 | — 未接入 | ○ 未接入 | — 未接入 |
| 当前产物 | arm64-v8a、armeabi-v7a、x86_64 APK | x64 portable ZIP | — | ○ 无 | — 无 |
| 运行要求 | Android 7+，targetSdk 37 | Windows 10 1809+；网页功能需要 WebView2 | 按 OHOS 文档为 API 26 方案草案 | iOS 15+ 工程配置，未验收 | — |
| 人工功能验收 | ◐ 仅部分记录 | ◐ 构建/启动冒烟为主 | — | ○ 无 | — |

## 4. 功能矩阵

### 4.1 共享能力与数据基础

| 功能 | Android | Windows | HarmonyOS NEXT | iOS | macOS |
| --- | --- | --- | --- | --- | --- |
| 业务/UI/状态/本地化 | ✅ | ✅ | — 高复用，需接入平台工程 | ◐ 共享代码可复用，待构建验收 | — 高复用，无工程 |
| 网络、账号、收藏、备份格式 | ✅ | ✅ | — 协议层可复用 | ◐ 协议层可复用 | — 协议层可复用 |
| SQLite 数据库 | ✅ `sqflite` 原生实现 | ✅ `sqflite_common_ffi` | — 需 OHOS 适配实现 | ◐ `sqflite_darwin` 路径存在，未验收 | — 可走 FFI，无工程 |
| 系统安全存储 | ✅ Android Keystore 路径 | ✅ Windows 加密存储路径 | — 需替换为 OHOS 安全存储插件 | ◐ Keychain 插件路径存在，未验收 | — 插件声明支持，无工程 |
| 网页登录与 Cookie 读取 | ✅ 系统 WebView | ✅ WebView2 | — WebView 适配是 P0 | ◐ WKWebView 插件路径存在，未验收 | — 插件声明支持，无工程 |
| 自适应导航/大屏双栏 | ✅ | ✅ | — 共享 UI 可复用 | ◐ 共享 UI 可复用 | — 共享 UI 可复用 |
| 无障碍语义与少动效 | ✅ 额外读取 Android 动画缩放/读屏状态 | ✅ 使用 Flutter 系统信号 | — 待接入系统信号 | ◐ 共享信号路径，待验收 | — 未适配 |
| 局域网 WebDAV | ✅ API 37 需运行时本地网络权限 | ✅ | — 需网络权限适配 | ○ Info.plist 尚无本地网络用途声明 | — 无工程 |

### 4.2 主题、窗口与导航

| 功能 | Android | Windows | HarmonyOS NEXT | iOS | macOS |
| --- | --- | --- | --- | --- | --- |
| 动态主题色 | ✅ 系统取色；不支持时回退固定主题色 | ✅ 跟随系统强调色 | — 建议首版降级为固定主题色 | ○ 当前取色插件无 iOS 实现 | ○ 插件支持 macOS，但现有代码主动禁用非 Windows 桌面动态色 |
| 明暗主题跟随系统 | ✅ | ✅ | ◐ 共享 `ThemeMode.system` 可复用 | ◐ 共享实现，待验收 | — 无工程 |
| OLED 纯黑深色 | ✅ | ✅ | ◐ 共享实现可复用 | ◐ 共享实现可复用 | — 无工程 |
| 窗口边框/标题栏跟随应用主题 | N/A | ✅ DWM 深色边框同步 | — | N/A | — 未适配 |
| 启动屏幕 | ✅ Android 12+ SplashScreen API，低版本启动窗口 | ○ 无专用启动图；窗口隐藏到 Flutter 首帧 | — | ◐ 默认 Flutter LaunchScreen 存在，未产品化验收 | — 无工程 |
| 系统栏 / edge-to-edge | ✅ | N/A | — 需安全区与系统栏适配 | ◐ Flutter 共享布局可复用 | — |
| 预测性返回 | ✅ Android 13+ 声明，页面转场支持跟手 | N/A | — 需系统返回语义适配 | ○ 不是 Android Predictive Back；普通侧滑返回由 Cupertino 转场提供 | — |
| 桌面鼠标侧键返回 | N/A | ✅ | — | N/A | — 未实现 |

### 4.3 文件、传输与二维码

| 功能 | Android | Windows | HarmonyOS NEXT | iOS | macOS |
| --- | --- | --- | --- | --- | --- |
| 选择文件上传 | ✅ 系统文件选择器，支持多选 | ✅ `file_picker` | — 需文件选择器适配 | ◐ `file_picker` 路径存在，未验收 | — 插件路径可复用 |
| 从其他应用/文档提供器上传 | ✅ 原生 `ACTION_GET_CONTENT`/文档提供器 | ○ 无独立入口 | — | ○ iOS 会显示入口，但对应自定义通道没有 Swift 实现 | — 无独立入口 |
| 二维码拍照识别 | ✅ 系统相机拍照后纯 Dart 解码，无需相机权限 | ○ 无拍照入口 | — 需要相机或图片选择能力 | ○ 界面会显示拍照，但自定义通道未实现 | — 无工程 |
| 二维码相册/图片识别 | ✅ | ✅ 系统文件选择 | — 图片选择 + 纯 Dart 解码可复用 | ◐ 图片选择与纯 Dart 解码可复用 | — 可复用，无工程 |
| 默认下载位置 | ✅ Android 10+ 公共 `Download/LanCloud`；旧系统回退应用目录 | ✅ 系统下载目录下的 `LanCloud` | — 需文档目录/公共目录适配 | ○ 当前共享路径会调用 iOS 不支持的 external storage API，需改为应用文档目录 | — 可走系统下载目录，无工程 |
| 公共 Downloads 写入 | ✅ Android 10+ MediaStore | N/A | — 需 OHOS 公共目录设计 | ○ 未实现 | — |
| 自定义下载目录 | ✅ SAF 持久授权；部分公共目录直接用路径 | ✅ 系统目录选择器 | — DocumentViewPicker/文件框架待适配 | ○ 当前无 iOS 专用目录授权实现 | — 可复用目录选择器，无工程 |
| “另存为”导出 | ✅ `ACTION_CREATE_DOCUMENT` | ✅ `file_picker` 保存 | — 需文件保存能力 | ○ 自定义保存通道没有 Swift 实现 | — 桌面保存路径可复用 |
| 打开已下载文件 | ✅ URI/FileProvider 经系统应用打开 | ✅ 文件关联程序 | — 需文件 URI 与 MIME 适配 | ◐ `open_filex` 路径可复用 | — `open` 路径可复用 |
| 分享/导出已下载文件 | ✅ 单文件、多文件系统分享 | ✅ 用资源管理器定位文件替代系统分享面板 | — 需 Share Kit | ○ 自定义分享通道没有 Swift 实现 | — 当前只会定位文件，不会调系统分享面板 |
| 多任务队列、暂停/继续、断点续传 | ✅ | ✅ | — Dart 逻辑可复用，存储与文件权限待适配 | ◐ Dart 逻辑可复用，待验收 | — Dart 逻辑可复用 |
| 应用在前台时传输 | ✅ | ✅ | ◐ 可复用 | ◐ 可复用 | — 无工程 |
| 移动端前台服务保活 | ✅ | N/A；窗口关闭即结束进程 | — 首版可能只能前台传输 | ○ 插件支持 iOS，但 Info.plist 未配置后台任务 | — |

### 4.4 系统集成

| 功能 | Android | Windows | HarmonyOS NEXT | iOS | macOS |
| --- | --- | --- | --- | --- | --- |
| 接收其他应用分享的文本/文件 | ✅ 已声明单文件和多文件 Intent | ○ 无系统分享接收 | — Share Kit/入口待实现 | ○ 插件支持 iOS，但分享扩展和 App Group 未配置 | — 无工程 |
| 作为蓝奏云链接默认打开方式 | ✅ 声明 `lanzoua.com` 至 `lanzouz.com` 的 `VIEW` 过滤 | ○ | — Ability/URI 入口待实现 | ○ 无 URL Types/Universal Links 声明 | — 无工程 |
| 拖拽文件 | ✅ | ✅；目录会展开为文件 | — 可选能力，插件需适配 | N/A | — `desktop_drop` 支持，无工程 |
| 拖拽分享链接文本 | ✅ | ○ Windows 插件拿不到拖拽文本 | — | N/A | — 桌面端当前同样只接收文件 |
| 识别剪贴板中的蓝奏云链接 | ✅ 默认关闭，回前台时读取 | ✅ | — 共享逻辑可复用 | ◐ 共享逻辑可复用，系统剪贴板提示待验收 | — 共享逻辑可复用 |
| 打开外部网页 | ✅ 优先 Custom Tabs，失败回退默认浏览器 | ✅ 默认浏览器 | — 系统浏览器/Ability | ◐ 默认浏览器路径可复用 | — 默认浏览器 |
| 生物识别/锁屏验证 | ✅ | ✅ Windows Hello 路径 | — 需 `local_auth` OHOS 适配 | ◐ 插件可走 Face ID/密码；缺 Face ID 用途声明，未验收 | — 插件声明支持，无工程 |
| 本地通知 | ✅ 传输进度、完成、收藏检测/更新、WebDAV 进度 | ✅ 完成/失败和消息提醒；不显示常驻进度 | — 基础通知优先，进度能力待验证 | ○ 当前初始化未包含 Darwin 平台设置 | ○ 当前初始化未包含 macOS 设置 |
| 通知权限管理 | ✅ | N/A | — | ○ 未接入系统权限流程 | — |
| 安装未知来源应用 | ✅ | N/A | — HAP 不能复用 APK 安装流程 | N/A | N/A |
| 忽略电池优化 | ✅ | N/A | — | N/A | N/A |
| 系统设置跳转/权限入口 | ✅ 通知、安装、电池优化；另有本地网络请求 | ○ 设置页隐藏 Android 专用入口 | — | ○ 当前过滤条件仍可能在 iOS 显示 Android 专用入口，但通道不存在 | — |
| 单实例窗口 | ✅ `singleTask` | ✅ 命名 Mutex + 激活已有窗口 | — | N/A | — |

### 4.5 更新与分发

| 功能 | Android | Windows | HarmonyOS NEXT | iOS | macOS |
| --- | --- | --- | --- | --- | --- |
| 应用内更新检查 | ✅ GitHub Release，按稳定/测试通道过滤 | ✅ 同一套检查 | — 不应继续使用 APK 逻辑 | ○ 更新入口显示“不支持”，不检查 GitHub | — 无工程 |
| 更新下载动作 | ✅ 按 ABI 选择 APK 后交给浏览器下载 | ✅ 打开 Windows portable ZIP 下载 | — 需 HAP 安装/市场更新方案 | ○ 无 | — 无 |
| 应用内自动替换/安装 | ○ 安装通道代码存在但当前未调用；更新按钮只打开下载页 | ○ 便携版需手动替换 | — | ○ 应由 App Store 管理 | — |
| Release 产物 | ✅ 三个 ABI APK | ✅ x64 portable ZIP | — HAP 未构建 | ○ 无 | — 无 |

## 5. 关键差异说明

### 5.1 动态取色与明暗主题

- Android 使用系统动态色板，取不到时回退用户选择的主题种子。
- Windows 使用系统强调色生成完整 Material 色板，因此设置页把这一项显示为
  “跟随系统”。
- iOS 当前的 `dynamic_color` 依赖没有 iOS 平台实现；macOS 虽有插件实现，
  `DynamicColorSupport` 仍主动把非 Windows 桌面判为不支持。
- 明暗模式本身是共享的 `ThemeMode.system`，不需要各平台重写；新平台主要验证
  系统亮度变化是否传到 Flutter。

### 5.2 文件选择不是同一种交互

- Android 普通上传使用系统文件选择器；单独的“从其他应用上传”走自定义
  `ACTION_GET_CONTENT`，可以把文档提供器内容复制到缓存。
- Windows 两类入口等价，因此不单独显示“从其他应用上传”。
- iOS 的普通上传理论上可复用 `file_picker`；但“从其他应用上传”目前仍被路由到
  Android 自定义通道，缺少 Swift 实现。
- 保存文件也分两条路：Android 走 `ACTION_CREATE_DOCUMENT`，桌面走
  `file_picker` 保存对话框。iOS 当前属于“非桌面”路径，会调用不存在的自定义
  通道，因此本地备份导出、日志导出会受影响。

### 5.3 下载目录与文件后续动作

- Android 最完整：公共 Downloads、固定路径、SAF 目录授权和 content URI
  打开/分享/删除并存。
- Windows 直接写普通文件路径，下载后可以打开或定位到资源管理器。
- iOS 当前下载路径仍沿移动端共享分支调用 external storage API，而
  `path_provider` 在 iOS 上不支持该 API；需要显式改为应用文档目录。它也没有
  专门的“文件”App 目录授权、分享面板或“另存为”实现。
- 后续平台应分别回答“下载到哪里”“用户能否改目录”“文件离开应用后 URI 是否
  仍有效”，不能只看传输队列能否跑通。

### 5.4 分享、深链和拖拽

- Android 已声明文本/文件分享入口、蓝奏云域名深链和系统拖拽通道。
- Windows 只实现文件拖入，拖拽文本不可用；没有接收系统分享和链接默认打开。
- iOS 的 `receive_sharing_intent` 插件声明支持 iOS，但要真正接收分享还需 Share
  Extension、App Group、Info.plist 和扩展目标配置；当前工程均没有。
- macOS 可复用 `desktop_drop` 的桌面文件拖入，但系统分享目前仍会被降级为
  “在文件管理器中定位”。

### 5.5 通知、前台服务与后台行为

- Android 进度通知使用常驻通知，前台服务覆盖传输、收藏检测和 WebDAV 备份。
- Windows 只显示完成/失败等消息，不显示常驻进度；最小化时进程仍可继续传输，
  关闭窗口后进程结束。
- iOS 插件本身支持 `flutter_foreground_task`，但项目尚未声明
  `UIBackgroundModes` 和 `BGTaskSchedulerPermittedIdentifiers`；通知初始化也没有
  `DarwinInitializationSettings`。
- HarmonyOS NEXT 的首版不应把“后台传输”当作核心能力门禁，优先保证前台传输和
  可恢复任务，再单独验证持续任务能力。
- 自动收藏检测和自动备份不是在系统后台常驻定时任务，所有平台都应沿用“启动/
  回前台补检”的产品语义。

### 5.6 生物识别与权限

- Android 使用 `FlutterFragmentActivity`，支持指纹/面部/锁屏验证；列表还管理
  通知、APK 安装和电池优化权限。
- Windows 使用 `local_auth_windows`，生物识别依赖 Windows Hello 可用性。
- iOS/macOS 的 `local_auth_darwin` 已在依赖中声明，但 iOS 还没有
  `NSFaceIDUsageDescription`，且未构建验收。生物识别不可用时，业务会回退为
  不允许显示 Cookie，而不是绕过验证。
- Android 17 的本地网络权限是运行时访问 WebDAV 前请求的能力，不属于设置页
  “管理权限”的三项列表。

### 5.7 更新

- “应用内更新”目前应理解为：应用内检查 GitHub Release、选择当前平台产物并
  打开下载地址。它不会自动下载、替换或安装。
- Android 的独立 `ApkInstaller` 通道存在，但当前没有 Dart 调用点；用户打开已
  下载 APK 时走的是系统文件打开/安装流程。
- Windows 更新后仍需手动解压并替换便携版。
- iOS 应使用 App Store/TestFlight，不能复用 GitHub APK/ZIP 更新；HarmonyOS
  NEXT 应使用应用市场或独立 HAP 安装策略。

## 6. 未来平台适配清单

### 6.1 HarmonyOS NEXT

详细方案、依赖候选和 HAP 发布流程见
[OHOS_ADAPTATION.md](./OHOS_ADAPTATION.md)。这里只列与功能矩阵直接相关的门禁：

- 建立独立 `ohos/` 目标或下游分支，不复用 Android 原生工程。
- 优先打通 WebView 登录/Cookie、安全存储、SQLite、文件选择和下载闭环。
- 提供文件 URI、打开、分享和用户目录授权适配；不要把 Android `content://`
  语义直接暴露给共享 UI。
- 验证基础通知与权限；进度通知、持续任务可作为第二阶段。
- 深链、分享接收、生物识别、动态色分别按能力开关显示或降级。
- HAP 更新与 APK 更新彻底分离，版本号和签名策略不能照搬 Android ABI 位。

### 6.2 iOS

共享 UI、API、数据库、Keychain、WebView 和标准文件选择具备较高复用价值。达到
可发布版本至少还需要：

- 实现 `lancloud/file_picker` 的 `takePhoto`、`saveFile`，以及“从其他应用上传”
  所需的等价行为；普通上传继续优先使用 `file_picker`。
- 修正 `DownloadPathService` 的 iOS 分支，使用应用文档目录或其他明确的 iOS
  文件位置，不要调用仅 Android 有效的 external storage API。
- 实现文件分享，或引入经过评估的系统分享插件；补齐 `lancloud/share` 调用点。
- 配置 Share Extension、App Group 和分享文件类型，验证冷启动/热启动收件箱。
- 为蓝奏云域名配置 URL Types 或 Universal Links，并实现
  `lancloud/links` 的初始/运行中链接投递。
- 补 `NSFaceIDUsageDescription`、相机/相册用途说明、本地网络用途说明等
  Info.plist 配置；实际键以最终采用的插件和系统 API 为准。
- 在通知初始化中加入 Darwin 平台设置与权限流程；如启用后台任务，补
  `UIBackgroundModes` 和任务标识。
- 修正 iOS 上仍显示 Android 专用入口的问题，确保不支持的功能隐藏而不是失败。
- 改为 App Store/TestFlight 分发，并建立签名、审核和隐私清单。

### 6.3 macOS

- 先创建 `macos/` 目标，逐个确认 `sqflite`、WebView、安全存储、文件选择、
  `desktop_drop` 和 `local_auth` 的 macOS 实现可用。
- `PlatformSupport.isDesktop` 会让文件打开、目录选择、拖拽等共享路径自动走桌面
  分支，但这只是起点；系统分享、通知和窗口主题仍需单独接入。
- 决定是否启用 `dynamic_color`。插件支持 macOS，但当前代码明确关闭了非 Windows
  桌面的动态取色。
- 补 macOS 通知初始化、沙盒网络/文件权限、签名和 notarization。
- 不应复用 Windows 的资源管理器定位作为“分享”；macOS 有必要调用原生分享面板。

## 7. 当前实现中的适配风险

| 风险 | 影响 | 处理方向 |
| --- | --- | --- |
| `!PlatformSupport.isMobile` 过滤 Android 专用设置 | iOS 仍会看到“管理权限”“默认链接”等入口，但自定义通道不存在 | 改为按能力判断，而不是按“是否移动端”判断 |
| 非桌面文件选择和保存统一进入 Android 通道 | iOS 的保存文件、拍照、从其他应用上传会失败 | 增加 iOS 实现或把能力路由到跨平台插件 |
| 移动下载路径直接调用 external storage API | iOS 默认下载目录解析会抛出不支持异常 | 在路径服务中按平台选择文档目录，并补下载落盘测试 |
| 通知初始化只声明 Android/Windows | iOS/macOS 即使接入目标也无法正常发本地通知 | 增加 Darwin 初始化与权限分支 |
| 全桌面平台共用“分享 = 复制文本/定位文件” | macOS 会失去原生分享体验 | 增加桌面分享能力适配，保留降级 |
| 所有移动端都被视为有相机和 Android 权限 | iOS UI 可能展示不可用入口 | 把 `isMobile` 拆成具体能力 |
| HAP 与 APK 更新语义不同 | 直接复用更新服务会向鸿蒙用户展示错误制品 | 使用独立 `UpdateAdapter` 和发布通道 |
| 后台自动任务只在启动/回前台补检 | 用户可能误以为关闭应用后仍会定时执行 | 在 UI、文档和商店说明中保持同一承诺 |

## 8. 代码证据入口

| 领域 | 先看 |
| --- | --- |
| 平台判定总入口 | [`lib/core/platform_support.dart`](../lib/core/platform_support.dart) |
| 主题与动态色 | [`lib/app.dart`](../lib/app.dart)、[`lib/core/dynamic_color_support.dart`](../lib/core/dynamic_color_support.dart)、[`lib/ui/theme_settings_tile.dart`](../lib/ui/theme_settings_tile.dart) |
| 文件选择与保存 | [`lib/core/file_picker_channel.dart`](../lib/core/file_picker_channel.dart)、[`lib/core/system_file_saver.dart`](../lib/core/system_file_saver.dart)、[`lib/core/saf_storage.dart`](../lib/core/saf_storage.dart) |
| 下载目标与公开 Downloads | [`lib/core/download_target.dart`](../lib/core/download_target.dart)、[`lib/core/download_path_service.dart`](../lib/core/download_path_service.dart)、[`lib/core/shared_downloads_storage.dart`](../lib/core/shared_downloads_storage.dart) |
| 打开、分享、拖拽 | [`lib/core/system_open.dart`](../lib/core/system_open.dart)、[`lib/core/system_share.dart`](../lib/core/system_share.dart)、[`lib/core/drag_drop.dart`](../lib/core/drag_drop.dart)、[`lib/ui/desktop_drop_target.dart`](../lib/ui/desktop_drop_target.dart) |
| 分享接收与深链 | [`lib/core/share_inbox.dart`](../lib/core/share_inbox.dart)、[`lib/core/incoming_links.dart`](../lib/core/incoming_links.dart) |
| 通知与前台任务 | [`lib/core/notifications.dart`](../lib/core/notifications.dart)、[`lib/core/foreground_task_coordinator.dart`](../lib/core/foreground_task_coordinator.dart)、[`lib/main.dart`](../lib/main.dart) |
| 生物识别与权限 | [`lib/core/cookie_auth.dart`](../lib/core/cookie_auth.dart)、[`lib/core/app_permissions.dart`](../lib/core/app_permissions.dart) |
| 更新与发布 | [`lib/core/update/update_service.dart`](../lib/core/update/update_service.dart)、[`.github/workflows/release.yml`](../.github/workflows/release.yml) |
| Android 原生实现 | [`MainActivity.kt`](../android/app/src/main/kotlin/com/lancloud/lancloud/MainActivity.kt)、[`AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) |
| Windows 原生实现 | [`flutter_window.cpp`](../windows/runner/flutter_window.cpp)、[`generated_plugin_registrant.cc`](../windows/flutter/generated_plugin_registrant.cc) |
| iOS 当前工程 | [`Info.plist`](../ios/Runner/Info.plist)、[`AppDelegate.swift`](../ios/Runner/AppDelegate.swift)、[`SceneDelegate.swift`](../ios/Runner/SceneDelegate.swift) |

## 9. 维护规则

- 新增平台能力时，同时更新本文对应行和“代码证据入口”，不要只改一张总表。
- `✅` 只用于已有平台实现/注册的当前平台；新增插件候选不能提前标为 `✅`。
- 每次完成 Android/Windows 的人工功能验收，可在对应格补“已验收”，并优先更新
  `BASELINE.md`，不要把构建成功当成功能验收。
- HarmonyOS NEXT 的平台方案改变时，先更新
  [OHOS_ADAPTATION.md](./OHOS_ADAPTATION.md)，再同步本文摘要。
- 新增第三方依赖或平台插件前，先确认已阅读 AGENTS.md 的依赖锁定规则并取得确认。
