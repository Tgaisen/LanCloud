# HarmonyOS NEXT integration notes

This branch is the downstream OHOS integration branch. Shared application code
still comes from `main`; this branch owns the ArkTS entry, OHOS dependency pins
and compatibility shims.

## Verified toolchain

- Flutter OH `3.47.7-ohos-1.0.0`
- Dart 3.13.3
- DevEco Studio 26.0.0.851
- HarmonyOS SDK 26.0.0 / API 26
- Tested device: HarmonyOS NEXT API 24, arm64

The project's Dart constraint and CI baseline are now compatible with both
official Flutter 3.47.7 and this OH Flutter tag.

## Environment

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:PATH = @(
  'C:\dev\flutter-ohos-3.47.7\bin',
  'C:\Program Files\Huawei\DevEco Studio\tools\node',
  'C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin',
  'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin',
  'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains',
  $env:PATH
) -join ';'
```

Use the normal Flutter storage mirror (`https://storage.flutter-io.cn`) for
`FLUTTER_STORAGE_BASE_URL`. OHOS-only artifacts already use their dedicated
storage endpoint.

## Build and test

```powershell
flutter pub get
flutter analyze
flutter build hap --debug --target-platform ohos-arm64 --no-codesign
```

The generated HAP is unsigned until a signing configuration is added in
DevEco Studio. Certificates, passwords and the local `.ohos/config` materials
must never be committed.

`flutter test` is currently run with the official Flutter 3.47.7 SDK, using the
same Material/Cupertino shims and the shared test suite. On the OH Flutter
3.47.7 host, `flutter test` fails before loading any test with
`Can't load Kernel binary: Invalid SDK hash`; `flutter analyze` and on-device
debug HAP execution are the verified OH-side checks until upstream fixes the
host `flutter_tester`/kernel pairing.

## Dependency pins

| Package | Source |
| --- | --- |
| `flutter_inappwebview` | CPF-Flutter tag `6.1.5-ohos-1.0.1` |
| `flutter_secure_storage_ohos` | CPF-Flutter tag `9.2.4-ohos-1.0.0` |
| `flutter_secure_storage` | vendored patched facade; see `packages/flutter_secure_storage/OHOS_PATCH.md` |
| `sqflite` | CPF-Flutter tag `2.4.2-ohos-1.0.0` |
| `path_provider_ohos` | commit `5d620c9b5d091547bdb3c324f83495e4460b24ee` |
| `shared_preferences_ohos` | commit `1562f7cc77e3bd2ca467ed2a927ee3497f3d96bf` |
| `material_ui` / `cupertino_ui` | local SDK-backed shims in `packages/` |

On Windows, enable Git long paths before resolving the WebView fork:

```powershell
git config --global core.longpaths true
```

## Current compatibility decision

The app module currently declares:

- `compatibleSdkVersion`: `6.1.1(24)`
- `targetSdkVersion`: `26.0.0`

This was needed to run debug HAPs on the available API 24 tablet. It is not yet
a product decision to support API 24 in production.

## Known blocker

Windows currently lacks a compatible arm64/OHOS AOT `gen_snapshot`. Debug HAPs
run on the device, but release HAPs built with the Windows x64 Dart tool produce
an x64 snapshot and fail at startup on arm64/OHOS. Build release artifacts on a
machine with the matching OHOS AOT toolchain until upstream publishes Windows or
Linux artifacts.

See [Phase 0 validation](../docs/OHOS_PHASE0_VALIDATION.md) for the full evidence.

## Phase 0 status

The formal `ohos/` project builds an unsigned ARM64 debug HAP and runs on an
API 24 HarmonyOS NEXT device after DevEco debug signing. The Cookie dialog
close/reopen path, WebView login, secure storage, SQLite, path provider, shared
preferences and a real drive listing have been exercised on device. Release
builds remain blocked by the missing arm64/OHOS AOT toolchain described above.

