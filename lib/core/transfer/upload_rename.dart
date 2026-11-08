import '../rename_rule.dart';

export '../rename_rule.dart';

// 兼容传输子系统的既有命名；批量规则本身已经提取为通用实现。
typedef UploadRenameTarget = RenameTarget;
typedef UploadRenameChange = RenameChange;
typedef UploadRenameError = RenameError;
typedef UploadRenamePreview = RenamePreview;
typedef UploadRenameRule = BatchRenameRule;
