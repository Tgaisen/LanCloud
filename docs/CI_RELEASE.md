# 发布 CI

GitHub Actions 的发布流程由 [`.github/workflows/release.yml`](../.github/workflows/release.yml)
驱动，复用 `tools/release/` 下的四段脚本：

| 阶段 | 本地脚本 | CI 任务 |
| --- | --- | --- |
| 校验 | `tools/release/validate.ps1` | `validate` |
| Android 构建 | `tools/release/build_android.ps1` | `android` |
| Windows 构建 | `tools/release/build_windows.ps1` | `windows` |
| 产物发布 | `tools/release/publish.ps1` | `release` |

`tools/release.ps1` 仍然保留，作为本地一键发版的编排入口；
`tools/build_windows.ps1` 是兼容入口，会转发到拆分后的 Windows 构建脚本。

## 触发方式

- **自动**：每次推送到 `main` 都会运行校验；当前版本尚未发布时才构建并
  创建 draft Release，已发布版本会直接跳过。
- **手动**：在 Actions 页面从 `main` 运行 `Release`，或执行：

  ```powershell
  gh workflow run release.yml -f draft=true
  ```

自动和手动触发都**默认创建 draft Release**。构建完成后到 GitHub Releases
页面检查产物和说明，确认无误再点发布。

如果运行一个已经发布过的版本，校验阶段会识别出来并跳过后续构建；
如果同名 Release 还是 draft，重新运行会覆盖上传产物，便于修复失败任务。

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

不要把 keystore、`key.properties`、Base64 文本或密码提交到仓库。
Android 构建结束后会用 `apksigner` 校验证书 SHA-256，指纹不匹配会直接失败，
避免漏配签名时把 debug 签名的包发出去。

## 产物

成功后会得到四个文件：

```text
LanCloud_android_<版本>_arm64-v8a.apk
LanCloud_android_<版本>_armeabi-v7a.apk
LanCloud_android_<版本>_x86_64.apk
LanCloud_windows_<版本>_x64_portable.zip
```

Android 在 Ubuntu runner 上构建；Windows 在 `windows-latest` 上构建。
Windows 构建需要 Visual Studio C++ 工具和 NuGet，GitHub 托管 runner 已提供，
workflow 会额外下载 NuGet CLI。

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

本地发布会检查工作区是否干净、`HEAD` 是否已经推送到 `origin/main`，以及
tag 是否已经存在。CI 构建从 `main` 的提交直接触发，不需要再在工作区里执行
`git push`。

## 常见问题

**Android 任务报缺少 secret**：按上面的表格配置四个 secrets，然后重新运行
workflow。

**版本已经发过，工作流被跳过**：这是预期行为。校验阶段发现 tag 指向
当前提交且 Release 已发布时，会输出 `should_release=false`。要发新版本，
先运行 `dart run tool/bump_version.dart` 并提交版本号变化。

**Windows 构建找不到 Visual Studio / NuGet**：本地先按
`tools/release/build_windows.ps1` 开头的提示安装 C++ 工作负载和 NuGet；
CI 使用托管 runner，不需要本地配置。

**Release 是 draft，怎么发布**：打开 Releases 页面，检查四个产物和自动生成的
变更说明后点击发布。draft 不会被普通用户看到，也不会被更新检查当作正式版本。
