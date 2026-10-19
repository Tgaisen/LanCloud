# HarmonyOS NEXT Phase 0 技术验证记录

> 验证日期：2026-10-19
>
> 验证对象：LanCloud `ohos` 分支（共享基线 `main` 提交 `69047f1`，
> 共享修复提交 `f6ea50f`）及 Flutter OH `3.47.7-ohos-1.0.0`
>
> 结论：**Gate A 的核心链路已在 HarmonyOS NEXT ARM64 真机 debug HAP 上
> 通过；Phase 0 的“立即处理”项已经落地并有自动化/真机证据；release/AOT
> 仍未通过。** 本记录不构成 release 可发布的结论。

## 1. 最终结果

| 检查项 | 结果 | 说明 |
| --- | --- | --- |
| OH-Flutter、DevEco Studio、API 26 SDK | 通过 | `flutter doctor -v` 中 HarmonyOS toolchain 可用 |
| HarmonyOS NEXT ARM64 真机识别 | 通过 | MatePad Pro，API 24，`arm64-v8a` |
| 空工程 ARM64 debug HAP 构建、安装、启动 | 通过 | 首次成功进入 Flutter 首帧 |
| LanCloud 隔离工程 ARM64 debug HAP 构建 | 通过 | 首轮 PoC，使用本地 shim 与固定 tag 插件 |
| 正式 `ohos` 工程 ARM64 debug HAP 构建 | 通过 | `flutter build hap --debug --target-platform ohos-arm64 --no-codesign` |
| LanCloud debug HAP 安装并进入协议页、登录页 | 通过 | 真机可操作 |
| Material/Cupertino shim 固化与共享测试 | 通过 | 官方 Flutter 3.47.7 + shim，539 项全部通过 |
| Cookie 弹窗取消、返回、校验后关闭与重开 | 通过 | 正式工程 signed debug HAP，真机 UI 自动化验证 |
| WebView 加载蓝奏云真实登录页 | 通过 | `flutter_inappwebview_ohos` |
| CookieManager 读取与登录闭环 | 通过 | 点击“完成登录”后进入首页 |
| 安全存储写入、读取、删除 | 通过 | 本地自检 `secure_storage=PASS` |
| SQLite 打开、建表、写入、查询、删除 | 通过 | 本地自检 `sqflite=PASS` |
| 正式 path_provider / shared_preferences 插件 | 通过 | 本地自检 `path_provider=PASS`、`shared_preferences=PASS` |
| 冷启动恢复账号 Cookie | 通过 | 强制停止后重启仍直接进入首页 |
| 真实网盘目录 API 与页面渲染 | 通过 | 根目录文件/文件夹列表正常显示 |
| ARM64 release HAP 构建 | 有条件通过 | 绕过 Windows AOT 工具缺失后可产出 HAP |
| ARM64 release HAP 运行 | **失败** | AOT snapshot 目标为 x64/Windows，与 arm64/OHOS 不匹配 |
| x64 模拟器运行 | **失败** | 旧引擎只认 kernel 130，当前 kernel 为 138 |
| 文件选择、下载、打开、分享、后台传输 | 未验证 | 属于后续 Phase 1/2 范围 |

Gate A 的“网页登录 + Cookie + 安全存储 + 数据库 + 真实页面”最低闭环已经
在 debug HAP 上跑通。发布 Gate 仍未通过。

## 2. 验证环境

| 组件 | 实际版本或状态 |
| --- | --- |
| 主机 | Windows 11，x86_64 |
| OH-Flutter | `3.47.7-ohos-1.0.0`，commit `e5a9c841b0` |
| 自带 Dart | 3.13.3 |
| DevEco Studio | 26.0.0.851 |
| HarmonyOS SDK | 26.0.0.105，API 26 |
| `ohpm` / `hvigorw` | 26.0.0.630 / 6.26.8 |
| 真机 | HUAWEI MatePad Pro `MRO-W00`，HarmonyOS 6.1.0.135，API 24，`arm64-v8a` |
| 模拟器 | Mate X7，HarmonyOS 7.0.0.107，API 26，`x86_64` |

关键环境变量：

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:PATH = @(
  'C:\Program Files\Huawei\DevEco Studio\tools\node',
  'C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin',
  'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin',
  'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains',
  $env:PATH
) -join ';'
```

`FLUTTER_STORAGE_BASE_URL` 保持常规的
`https://storage.flutter-io.cn`。将其设置为 OHOS OBS 会导致通用 Flutter
工件 `engine_stamp.json`、`flutter_gpu.zip` 返回 404。

## 3. x64 模拟器：首轮失败

空工程 x64 debug HAP 可以构建并安装，但启动后停留在 Flutter 启动页。
hilog 中的错误为：

```text
Dart Error: Can't load Kernel binary:
Invalid kernel binary format version (expected 130, found 138).
Could not prepare kernel isolate.
Could not create root isolate.
```

原因是 `3.47.7-ohos-1.0.0` Release 没有提供 x64 引擎，x64 仍使用旧 OBS
工件（Dart 3.12.x / kernel 130）。**该模拟器路径当前不可用。**

## 4. ARM64 真机：debug 闭环通过

真机首次安装未签名 HAP 时返回 `no signature file`。使用 DevEco 自动调试
签名后，空工程成功安装并进入 Flutter Demo 首帧。

随后把真实 LanCloud 代码和 OHOS 平台入口放入隔离工程，逐步补齐 `material_ui`
、`cupertino_ui`、path provider、安全存储、SQLite 和 WebView 后，真实应用
可以完成以下流程：

1. 启动并显示首次运行协议页。
2. 同意协议进入登录页。
3. 打开网页登录，WebView 加载蓝奏云真实登录页。
4. 点击“完成登录”，通过 CookieManager 读取 WebView 登录 Cookie。
5. 校验通过后进入首页。
6. 强制停止并重新启动，账号仍能从安全存储恢复，直接进入首页。
7. 打开“网盘”页，真实账号的根目录文件/文件夹列表正常显示。

首轮隔离工程随后被正式 `ohos` 工程取代。最终用于本轮 Cookie 弹窗回归的
signed debug HAP 由正式工程副本构建：

```text
entry-default-signed.hap
212,056,016 bytes
SHA-256: A57FDBC5DC261EDA76737F4DFEDCB314D02A6C1541CC941FDDB92DCE11CDD898
```

该构建的 bundle 仍是临时调试包 `com.example.myapplication`，签名材料只在
被 Git 忽略的 `outputs/` 副本中使用。设备当前保留该可运行的 debug 构建。

## 5. 核心能力验证

### 5.1 WebView 与 Cookie

- 使用 CPF-Flutter 固定 tag `6.1.5-ohos-1.0.1`。
- 该仓库公开验证矩阵只到 Flutter 3.35，但本次在 Flutter OH 3.47.7 上
  成功编译并运行。
- 页面可加载蓝奏云登录页；CookieManager 通道已注册。
- 本次没有输入或读取账号密码，使用的是设备上已有的 WebView 登录会话。
- 完成登录后应用进入首页，随后冷启动仍能恢复账号。

### 5.2 安全存储

- 使用 CPF-Flutter 固定 tag `9.2.4-ohos-1.0.0`。
- 自检结果最初失败，堆栈定位到 fork 主包漏写了
  `Platform.operatingSystem == 'ohos'` 分支。
- 已在 `ohos/packages/flutter_secure_storage` 固定并修补 Dart facade，
  来源 commit `ecc4257040163da3c4dd64d4fced5d4d24676a53`；补丁说明见
  `ohos/packages/flutter_secure_storage/OHOS_PATCH.md`。
- 补上 OHOS 分支后：

```text
phase0: secure_storage=PASS
```

- 真实账号 Cookie 在强制停止/冷启动后恢复成功。

### 5.3 SQLite

- 使用 CPF-Flutter 固定 tag `2.4.2-ohos-1.0.0`。
- 启动自检完成建库、建表、插入、查询和删除：

```text
phase0: sqflite=PASS
```

- `AppDb` 实际数据库已落盘：

```text
/data/app/el2/100/database/com.example.myapplication/rdb/lancloud.db
```

### 5.4 真实网盘页面

登录后可以正常加载账号根目录，文件夹名称、图标、锁定/备份标记均正常；
说明 Cookie、网络请求、JSON 解析、数据库和 Flutter 页面渲染链路可用。

## 6. Phase 0 “立即处理”落地结果

| 项目 | 正式落地方式 | 验证 |
| --- | --- | --- |
| Material / Cupertino shim | `ohos/packages/material_ui`、`ohos/packages/cupertino_ui` 重导出 OH-Flutter SDK 的 Material/Cupertino，并通过 `dependency_overrides` 接入 | 官方 Flutter 3.47.7 下编译同一组 shim，共享测试 539 项全部通过；OH-Flutter `flutter analyze` 无问题 |
| Dart 约束 | 根 `pubspec.yaml` 调整为 `sdk: ^3.13.3`，`pubspec.lock` 同步 | 同时兼容官方 Flutter 3.47.7 与 OH-Flutter 的 Dart 3.13.3 |
| path_provider | `path_provider_ohos`，固定 commit `5d620c9b5d091547bdb3c324f83495e4460b24ee` | 真机自检 `path_provider=PASS` |
| shared_preferences | `shared_preferences_ohos`，固定 commit `1562f7cc77e3bd2ca467ed2a927ee3497f3d96bf` | 真机自检 `shared_preferences=PASS` |
| WebView | `flutter_inappwebview` CPF-Flutter tag `6.1.5-ohos-1.0.1` | 真机网页登录、CookieManager 读取闭环通过 |
| 安全存储 | CPF-Flutter tag `9.2.4-ohos-1.0.0` + vendored OHOS 分支补丁 | 真机 `secure_storage=PASS`，冷启动恢复账号成功 |
| SQLite | CPF-Flutter `sqflite` tag `2.4.2-ohos-1.0.0` | 真机 `sqflite=PASS`，真实数据库落盘 |
| Cookie 弹窗生命周期 | 控制器移入 `StatefulWidget` 的 State，在 `dispose()` 中释放 | 单元测试通过；真机取消、系统返回、空输入校验后关闭、重开全部正常，无红屏 |
| 签名 | 仅在被 Git 忽略的 `outputs/` 副本注入 DevEco 自动调试签名，bundle 为 `com.example.myapplication` | signed debug HAP 安装并运行；签名材料未进入仓库 |
| 兼容版本 | `compatibleSdkVersion` 为 `6.1.1(24)`，`targetSdkVersion` 为 `26.0.0` | API 24 真机 debug 通过；正式最低 API 仍待产品确认 |

### 6.1 自动化测试限制

- 官方 Flutter 3.47.7 下，使用固化后的 Material/Cupertino shim 编译完整共享
  测试，结果为 `01:19 +539: All tests passed!`。
- OH-Flutter 3.47.7 下的 `flutter analyze` 通过；但 `flutter test` 在加载
  测试前失败：

```text
Dart Error: Can't load Kernel binary: Invalid SDK hash.
Could not prepare isolate.
Could not create root isolate.
```

  已清理项目 `.dart_tool` 并使用独立 `PUB_CACHE` 复现，属于宿主
  `flutter_tester`/kernel 与 SDK 的配套问题，不是测试用例失败。当前以官方
  Flutter 的完整测试 + OH-Flutter 的静态分析和真机运行共同覆盖。

### 6.2 仍需关注的风险

- `path_provider_ohos` 与 `shared_preferences_ohos` 来自较小的社区仓库。
  当前已固定 commit 且通过 API 24 真机验证，但长期维护、安全修复和升级
  责任需要工程/产品确认；必要时改为 vendored 固定副本。
- Material/Cupertino 仍是 SDK 重导出 shim，需随 OH-Flutter SDK 升级继续
  跑完整共享测试。
- WebView fork 需要在 3.47.7 下建立更完整的页面、键盘、旋转和 Cookie
  回归矩阵。
- Windows 上的 release/AOT 阻塞仍未解除，见第 7 节。

## 7. Release/AOT 仍被阻塞

Windows OBS 中的 `ohos-arm64-release/windows-x64/gen_snapshot.exe` 是旧
Dart 3.12.2 工具，且实际目标为 `windows_simarm64`。官方 Release 只提供
Darwin 主机的新 `gen_snapshot`。

临时把 SDK 自带的 Dart 3.13.3 `gen_snapshot.exe` 复制到 AOT 工具目录，
并关闭图标 tree-shaking，可以产出约 70.3 MB 的 signed release HAP。但该
HAP 启动时报：

```text
Snapshot not compatible with the current VM configuration:
the snapshot requires '... x64 windows ...'
but the VM has '... arm64 ohos compressed-pointers'
Could not create root isolate.
```

因此 **release HAP 只完成了构建动作，不能运行**，不能用于发布验收。
需要：

1. 在 macOS 主机使用官方同版本 `gen_snapshot` 构建；或
2. 由 OH-Flutter 上游补齐 Windows/Linux 的 arm64 OHOS AOT 工具；或
3. 自行从匹配源码构建完整 OHOS 引擎与 AOT 工具链。

## 8. 后续建议

### 已完成（Phase 0 立即处理）

1. [x] 固化 `material_ui` / `cupertino_ui` shim，并跑完整共享测试。
2. [x] 将 Dart 约束调整为与固定 OH-Flutter tag 一致的 `3.13.3`。
3. [x] 用固定 commit 的 OHOS 插件替换临时 `shared_preferences` 和
   path provider 实现。
4. [x] 修复 Cookie 弹窗控制器释放时机，并提交到主工程。
5. [x] 把安全存储 fork 的 OHOS 分支修复固定到 tag/commit 和 vendored 补丁。

### 进入 Phase 1 前需确认

- 是否接受 API 24 作为正式最低版本；当前配置只是为现有测试设备所做的
  PoC 决策。
- `path_provider_ohos`、`shared_preferences_ohos` 的长期维护策略。
- release/AOT 的构建主机和 CI 方案；在解决前不能承诺可发布 HAP。

### Phase 1

- 文件选择、应用沙箱下载、用户目录选择、打开/分享、重名处理。
- 通知、分享入口、深链、系统返回和折叠屏/分屏布局。
- 在 release AOT 可用后，对 debug/release 各跑一轮核心回归。

### 产品决策

- 确认最低支持 API。OH-Flutter Release Note 声明 API 26，当前工程为适配
  API 24 真机使用 PoC 配置；不能据此承诺 API 24 的完整发布支持。
- 确认正式 bundle、应用图标/权限文案、调试与发布签名、HAP 更新策略。

## 9. 本地证据

以下文件位于被 Git 忽略的 `outputs/ohos-phase0/`：

- `device_verify_20261019/`：由正式 `ohos` 工程副本构建的 signed debug
  HAP、布局树和 Cookie 弹窗回归截图；HAP 校验和见第 4 节。
- `device_verify_20261019/cookie_empty.jpeg`：Cookie 弹窗空输入校验与
  正常渲染。
- `shim_tests_20261019/`：官方 Flutter 3.47.7 下 Material/Cupertino
  shim 的完整共享测试工程。
- `lancloud_final_debug.jpeg`：最终可运行的 LanCloud 首页。
- `lancloud_drive.jpeg`：真实网盘根目录列表。
- `lancloud_webview2.jpeg`：WebView 蓝奏云登录页。
- `lancloud_restart.jpeg`：强制停止后冷启动仍保持登录。
- `lancloud_release.jpeg`：release HAP 白屏。
- `phase0.jpeg`、`phase0_after.jpeg`：x64 模拟器启动页白屏。
- `lancloud_project/`：真实工程隔离副本、插件、日志和 signed debug HAP。
- `lancloud_phase0/`：空工程、x64 构建与 ARM64 release PoC。

