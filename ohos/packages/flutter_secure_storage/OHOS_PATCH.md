# flutter_secure_storage OHOS patch

Source: CPF-Flutter `fluttertpc_flutter_secure_storage`,
tag `9.2.4-ohos-1.0.0` (commit
`ecc4257040163da3c4dd64d4fced5d4d24676a53`).

The fork's Dart facade declares OS-specific options but its `_selectOptions`
method omitted the OHOS branch, so every read/write failed with
`Unsupported operation: unsupported_platform` before reaching the native plugin.

This vendored package adds the missing branch and relies on the documented
defaults implemented by `flutter_secure_storage_ohos`. Keep this patch until an
upstream tag contains the same fix.

