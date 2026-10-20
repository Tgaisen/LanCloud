import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/api/lanzou_client.dart';
import 'package:lancloud/l10n/l10n.dart';

void main() {
  test('API 固定错误按界面语言本地化，服务端原文保持兜底', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));

    const rename = LanzouException(
      'fallback',
      code: LanzouErrorCode.renameRequiresMembership,
    );
    expect(zh.lanzouError(rename), '重命名失败：此功能需要开通会员');
    expect(
      en.lanzouError(rename),
      'Rename failed: This feature requires a membership',
    );

    expect(
      en.lanzouError(const NeedPasswordException()),
      'This share requires a password',
    );
    expect(
      en.lanzouError(const WrongPasswordException()),
      'Incorrect password',
    );
    expect(
      en.lanzouError(
        const LanzouException(
          'fallback',
          code: LanzouErrorCode.uploadFailed,
          detail: 'server busy',
        ),
      ),
      'Upload failed: server busy',
    );

    // 服务端直接返回的动态文案没有可翻译的 code，保留原文。
    expect(en.lanzouError(const LanzouException('服务端返回的原文')), '服务端返回的原文');
  });
}
