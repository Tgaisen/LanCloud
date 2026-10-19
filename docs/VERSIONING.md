# 版本号规范

版本名为： `年份(YY).内容更新序号(Drop).热修号(Hotfix)[-阶段(Stage).序号(Seq)]`

Android versionCode（9 位）按位拼接：
`YY Drop Hotfix ABI Stage Seq`

`YY * 10^7 + Drop * 10^5 + Hotfix * 10^4 + ABI * 10^3 + Stage * 10^2 + Seq`

| 位 | 含义 |
| --- | --- |
| 1–2 | 年份 YY（`26`） |
| 3–4 | 内容更新序号 Drop（`01`） |
| 5 | 热修号 Hotfix（`0`–`9`） |
| 6 | ABI：`0` universal（预留）/ `4` armeabi-v7a / `7` arm64-v8a / `8` x86_64 |
| 7 | 阶段：`snapshot` = 1 / `pre`、`beta` = 2 / `rc` = 3 / 正式版 = 9 |
| 8–9 | Seq（`01`–`99`；正式版固定 `99`） |

示例：

| 版本 | APK | versionCode |
| --- | --- | --- |
| `26.1.0-pre.10` | universal（预留，ABI = 0） | `260100210` |
| `26.1.0-pre.10` | armeabi-v7a | `260104210` |
| `26.1.0-pre.10` | arm64-v8a | `260107210` |
| `26.1.0-pre.10` | x86_64 | `260108210` |
| `26.1.0` | arm64-v8a | `260107999` |

- `pubspec.yaml` / `lib/core/app_info.dart` 里存的是 **ABI = 0 的基准号**
  （如 `260100210`）；构建时由 `android/app/build.gradle.kts` 按实际 ABI
  加上 `digit * 1000`。Flutter 自带的 ABI 偏移（+1000 / +2000 / +4000）
  已在 `android/gradle.properties` 用
  `force-version-code-ignoring-abi=true` 关掉，改由上面这套位段控制。
- 同一台设备的 ABI 不会变，所以升级只需要看阶段与 Seq：`Seq + 1` 永远比
  上一次大；Seq 到 99 后进入下一阶段（snapshot → pre → rc → 正式版），或换
  下一个热修号 / 内容更新序号。旧方案已发布的 arm64 `26.1.0-pre.9` 是
  `260104009`，新方案 `26.1.0-pre.10` 的 arm64 是 `260107210`，可直接覆盖。
- 官方 Release 与本地安装包都用 `--split-per-abi` 构建（每个 ABI 一个 APK）。
  `universal` 位 `0` 目前只是占位；上架 Google Play 时需要恢复按 ABI 区分的
  versionCode（去掉 `gradle.properties` 里那一项，改用 Play 的拆包规则）。

**开发构建（装到设备 / 分发测试包）**

- 每次要安装或分发的构建都换一个新版本名：`Seq + 1`（例如 `26.1.0-pre.9`
  → `26.1.0-pre.10`）。versionCode 由公式推出，同一 ABI 上天然比上一次大，
  不会出现需要降级安装的情况。
- 用脚本一步完成（同时改 `pubspec.yaml` 和 `lib/core/app_info.dart`）：

  ```powershell
  dart run tool/bump_version.dart                 # Seq +1
  dart run tool/bump_version.dart --dry-run       # 只打印结果
  dart run tool/bump_version.dart --set <新版本名>  # 换内容更新序号 / 进入下一阶段
  ```

- 不要再用 `flutter build --build-number` 临时顶高 versionCode：那会绕开
  版本名，把「安装顺序」和「版本号」混在一起。同一版本号重复构建只适合
  本机覆盖调试，不要用来分发。
- 每个阶段有 99 个序号（versionCode 的最后两位）；用满后进入下一阶段
  （snapshot → pre → rc → 正式版），或换下一个热修号 / 内容更新序号。
- 推送到 `main` 后，Release CI 会检查当前版本；尚未发布时自动构建
  Android / Windows 并创建 draft Release。发布说明和 CI 签名配置见
  [CI_RELEASE.md](CI_RELEASE.md)。
