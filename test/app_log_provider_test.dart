import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/app_log.dart';
import 'package:lancloud/core/app_log_provider.dart';

void main() {
  test('appLogProvider 暴露应用唯一日志服务', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(appLogProvider);
    final second = container.read(appLogProvider);

    expect(identical(first, AppLog.instance), isTrue);
    expect(identical(first, second), isTrue);
  });
}
