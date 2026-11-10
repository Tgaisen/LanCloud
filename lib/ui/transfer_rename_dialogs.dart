import 'package:material_ui/material_ui.dart';

import '../core/transfer/transfer_manager.dart';
import '../core/transfer/upload_rename.dart';
import 'rename_dialogs.dart';

/// 单个上传任务的名称修改。
Future<String?> showSingleUploadRenameDialog(
  BuildContext context, {
  required TransferTask task,
}) {
  return showRenameDialog(
    context,
    initialName: task.name,
    kind: RenameTargetKind.file,
    keyPrefix: 'upload-rename',
  );
}

/// 批量上传任务的查找替换与预览。
Future<List<UploadRenameChange>?> showBatchUploadRenameDialog(
  BuildContext context, {
  required List<TransferTask> tasks,
}) {
  return showBatchRenameDialog(
    context,
    targets: [
      for (final task in tasks)
        UploadRenameTarget(
          id: task.id,
          name: task.name,
          kind: RenameTargetKind.file,
        ),
    ],
    keyPrefix: 'upload-batch-rename',
  );
}
