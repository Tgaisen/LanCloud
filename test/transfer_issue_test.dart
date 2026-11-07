import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/transfer/transfer_issue.dart';

void main() {
  test('传输问题码可持久化并还原大小详情', () {
    const issue = TransferIssue(TransferIssueCode.skippedOversize, '100 MB');

    final decoded = TransferIssue.decode(issue.encode());

    expect(decoded?.code, TransferIssueCode.skippedOversize);
    expect(decoded?.detail, '100 MB');
  });

  test('兼容旧版本已保存的中英文被跳过原因', () {
    expect(
      TransferIssue.decode('此类文件不允许上传')?.code,
      TransferIssueCode.skippedUnsupported,
    );
    expect(
      TransferIssue.decode('File type is not in the allowed upload list')?.code,
      TransferIssueCode.skippedUnsupported,
    );
    final oversize = TransferIssue.decode('文件超过 10 MB 限制');
    expect(oversize?.code, TransferIssueCode.skippedOversize);
    expect(oversize?.detail, '10 MB');
    expect(
      TransferIssue.decode('Exceeds the per-file limit (100 MB)')?.code,
      TransferIssueCode.skippedOversize,
    );
  });

  test('切换账号中断可被持久化识别，供任务重试', () {
    const issue = TransferIssue(
      TransferIssueCode.uploadInterruptedByAccountSwitch,
    );

    expect(
      TransferIssue.decode(issue.encode())?.code,
      TransferIssueCode.uploadInterruptedByAccountSwitch,
    );
  });
}
