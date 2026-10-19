# material_ui OHOS shim

The pub.dev `material_ui` implementation does not enumerate
`TargetPlatform.ohos` in all of its exhaustive switches. Flutter OH still ships
the complete Material implementation as `package:flutter/material.dart`.

This package keeps the dependency name and public entrypoints used by LanCloud
while re-exporting that SDK implementation.

