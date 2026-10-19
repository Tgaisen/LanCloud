# 发布 CI

GitHub Actions 的发布流程由 [`.github/workflows/release.yml`](../.github/workflows/release.yml)
驱动，复用 `tools/release/` 下的四段脚本：

| 阶段 | 本地脚本 | CI 任务 |
| --- | --- | --- |
| 校验 | `tools/release/validate.ps1` | `validate` |
| Android 构建 | `tools/release/build_android.ps1` | `android` |
| Windows 构建 | `tools/release/build_windows.ps1` | `windows` |
| 产物发布 | `tools/release/publish.ps1` | `release` |

发版脚本已拆成校验、Android 构建、Windows 构建、产物发布四段；日常发版走
CI，本地一键发布也复用同一组脚本。

`tools/release.ps1` 仍然保留，作为本地一键发版的编排入口；
`tools/build_windows.ps1` 是兼容入口，会转发到拆分后的 Windows 构建脚本。

## 触发方式

- **自动**：每次推送到 `main` 都会运行
  [Release workflow](https://github.com/Tgaisen/LanCloud/actions/workflows/release.yml)
  的校验；当前版本尚未发布时才构建并创建 draft Release，已发布版本会直接跳过。
- **手动**：在 Actions 页面从 `main` 运行 `Release`，或执行：

  ```powershell
  gh workflow run release.yml -f draft=true
  ```

自动和手动触发都**默认创建 draft Release**。构建完成后到 GitHub Releases
页面检查产物和说明，确认无误再点发布。

只有确认不需要人工检查时，才用 `-f draft=false` 直接发布。手动运行时请选择
`main` 分支。

如果运行一个已经发布过的版本，校验阶段会识别出来并跳过后续构建；
如果同名 Release 还是 draft，重新运行会覆盖上传产物，便于修复失败任务。

注意：如果当前版本尚未发布，任意一次 `main` push（包括只改文档）都可能
触发首次 draft 构建；发布完成后，同一版本的后续推送会快速跳过构建。

### 最短发版流程

1. 运行 `dart run tool/bump_version.dart` 更新版本号，确认
   `pubspec.yaml` 与 `lib/core/app_info.dart` 一致。
2. 提交并推送到 `main`。
3. 等待 `Release` workflow 的校验、Android、Windows、发布四个任务全部成功。
4. 打开 [Releases](https://github.com/Tgaisen/LanCloud/releases)，检查四个
   产物和发布说明，确认后点击发布。

如果构建失败，修复后重新运行整个 workflow；详见下面的常见问题。

## 必需的 Android 签名 secrets

CI 没有本地的 `android/key.properties`，因此必须在仓库
`Settings → Secrets and variables → Actions` 中配置以下 secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | release keystore 的 Base64 文本 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

在已配置好本地签名的机器上，可以用 GitHub CLI 上传。先确认
`android/key.properties` 里的 `storeFile` 指向正确的 keystore：

```powershell
$keystore = 'C:\path\to\lancloud-release.jks'  # 换成 storeFile 指向的文件
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))
$base64 | gh secret set ANDROID_KEYSTORE_BASE64

# 下面三条会交互式读取，不会把密码写进 PowerShell 历史
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

`key.properties` 里的 `storeFile` 如果是相对路径，Gradle 会按
`android/app/` 解析；按上面的方式上传时请确认实际指向的文件。

GitHub 不允许重新读取 secret 原文。配置完成后，最直接的验证方式是运行一次
`Release` workflow，确认 Android 任务的「配置 release 签名」和「构建并校验签名」
两步都成功；后者会实际检查证书 SHA-256。

不要把 keystore、`key.properties`、Base64 文本或密码提交到仓库。
Android 构建结束后会用 `apksigner` 校验证书 SHA-256，指纹不匹配会直接失败，
避免漏配签名时把 debug 签名的包发出去。

上传完成后请删除临时生成的 Base64 文本（例如
`android/app/keystore.base64.txt`）。该路径已经加入 `.gitignore`，但它仍然是
签名私钥的可还原副本。

## 依赖锁定与 Android 启动回归

`pubspec.lock` 使用 Flutter 中国镜像生成。Release workflow 固定设置同一个
`PUB_HOSTED_URL`，并在三个任务里用 `flutter pub get --enforce-lockfile`
取依赖；两个构建脚本也会给 `flutter build` 传 `--no-pub`，避免构建阶段再次
解析依赖。不要删掉这些保护，否则 GitHub runner 使用不同包源时可能忽略
lock 中的版本并自动升级。

`pubspec.yaml` 将 `shared_preferences_android` 固定在 `<2.5.0`。2.5.0 的
release/R8 构建会丢掉 JNI 使用的 Kotlin 挂起方法签名，启动时
`SharedPreferencesApiRegistrar.getAll` 抛出 `NoSuchMethodError`，界面会永久
停在启动页。上游修复正式发布前不要移除这个限制；升级依赖后必须生成新的
APK 并在 Android 真机或模拟器上实际启动验证：

```text
https://github.com/flutter/flutter/issues/194649
```

## 权限与运行环境

- workflow 使用 GitHub Actions 内置的 `GITHUB_TOKEN`，并声明
  `contents: write`，用于创建 tag 和 Release；不需要额外的 Personal Access Token。
- Android 在 `ubuntu-latest` 构建，安装 JDK 17、Android SDK Platform 37.0、
  build-tools 36.0.0、NDK 28.2.13676358 和 CMake 3.22.1。Android 15/17
  启动白屏已定位为依赖解析问题，不是 Linux 构建链问题，因此不需要固定到
  Windows runner。
- Windows 在 `windows-latest` 构建，workflow 会启用开发者模式并准备 NuGet，
  以支持 Flutter 插件符号链接和 WebView2 SDK。
- 首次运行需要下载 SDK、Gradle、Flutter 引擎等冷缓存内容，通常比后续运行慢；
  当前实测整条 Release workflow 约 13–20 分钟。任务显示进行中但暂时没有
  新日志时，先等待构建步骤完成。
- tag 只在 Android 和 Windows 都构建成功后的 `release` job 中创建；如果上传
  阶段失败，tag 或 draft 可能已经存在，重跑同一个 workflow 会补齐或覆盖产物。

## 产物

成功后会得到四个文件：

```text
LanCloud_android_<版本>_arm64-v8a.apk
LanCloud_android_<版本>_armeabi-v7a.apk
LanCloud_android_<版本>_x86_64.apk
LanCloud_windows_<版本>_x64_portable.zip
```

Windows 产物是绿色便携版，解压后运行；内嵌网页功能仍需要系统安装 WebView2
运行时。构建目录中的 `lancloud.exe.WebView2` 属于本机运行数据，不会被打进
发布 zip。

## 本地发版

本地流程与 CI 共用同一组脚本：

```powershell
# 校验 + Android + Windows + 创建正式 Release
powershell -ExecutionPolicy Bypass -File tools/release.ps1

# 先建 draft
powershell -ExecutionPolicy Bypass -File tools/release.ps1 -Draft

# 只做检查，不构建、不发布
powershell -ExecutionPolicy Bypass -File tools/release.ps1 -DryRun
```

常用参数：

| 参数 | 用途 |
| --- | --- |
| `-Draft` | 本地创建 draft Release |
| `-SkipTests` | 跳过格式检查、静态分析和测试 |
| `-SkipWindows` | 只构建 Android |
| `-SkipAndroid` | 只构建 Windows |
| `-DryRun` | 只打印将执行的命令 |
| `-NotesFile <路径>` | 指定手写发布说明 |

本地发布会检查工作区是否干净、`HEAD` 是否已经推送到 `origin/main`，以及
远端 tag 是否已经存在。CI 会从 `main` 的提交直接构建，不需要你在本地手动
打 tag 或推送 tag；`release` job 会在产物齐全后创建并推送 `v<版本>`。

`tools/release.ps1` 默认创建正式 Release，只有加 `-Draft` 才建草稿；
CI 的默认行为正好相反，自动和手动触发都默认建草稿。

## 发布说明

本地发布时，`-NotesFile` 优先级最高；不传时先找
`docs/releases/<版本>.md`，再回退到 `gh --generate-notes`。

CI 默认使用自动生成的发布说明。仓库目前忽略 `docs/releases/*.md`，所以
普通提交不会把自定义说明带进 CI；如果确实要在 CI 使用固定文案，需要在发布
前提交该文件（例如 `git add -f`），或调整 `.gitignore` 规则。

## 常见问题

**Android 任务报缺少 secret**：按上面的表格配置四个 secrets，然后重新运行
workflow。

**版本已经发过，工作流被跳过**：这是预期行为。校验阶段发现 tag 已指向
其他提交，或当前 tag 对应的 Release 已经发布时，会输出
`should_release=false`。要发新版本，先运行
`dart run tool/bump_version.dart` 并提交版本号变化。

**CI 失败了怎么重跑**：在 Actions 页面打开对应的 `Release` run，选择
`Re-run all jobs`；也可以执行 `gh run rerun <run-id>`。重新运行会基于同一个
提交重建产物，并补齐同名 draft Release。

**Windows 构建找不到 Visual Studio / NuGet**：本地先按
`tools/release/build_windows.ps1` 开头的提示安装 C++ 工作负载和 NuGet；
CI 使用托管 runner，不需要本地配置。

**Release 是 draft，怎么发布**：打开 Releases 页面，检查四个产物和发布说明
（默认自动生成）后点击发布。draft 不会被普通用户看到，也不会被更新检查
当作正式版本。

**构建很慢或看起来没有日志**：首次运行要下载 SDK、Gradle 和 Flutter 引擎，
构建步骤可能长时间没有新日志。当前实测整条流程约 13–20 分钟，先看 job
是否仍在 `in_progress`，不要急着取消。
