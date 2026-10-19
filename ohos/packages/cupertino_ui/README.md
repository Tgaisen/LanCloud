# cupertino_ui OHOS shim

The pub.dev `cupertino_ui` implementation does not enumerate
`TargetPlatform.ohos` in all of its exhaustive switches. Flutter OH still ships
the complete Cupertino implementation as `package:flutter/cupertino.dart`.

This package keeps the dependency name and public entrypoints used by LanCloud
while re-exporting that SDK implementation.

