import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/l10n/app_localizations.dart';
import 'package:lancloud/ui/common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations zh;
  late AppLocalizations en;
  final now = DateTime(2026, 10, 15, 14, 30);

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('即时层 / 近期层：刚刚、N分钟前', () {
    expect(
      formatRelativeTime(
        zh,
        now.subtract(const Duration(seconds: 30)),
        now: now,
      ),
      '刚刚',
    );
    expect(
      formatRelativeTime(
        zh,
        now.subtract(const Duration(minutes: 1)),
        now: now,
      ),
      '1分钟前',
    );
    expect(
      formatRelativeTime(
        zh,
        now.subtract(const Duration(minutes: 5)),
        now: now,
      ),
      '5分钟前',
    );
    expect(
      formatRelativeTime(
        zh,
        now.subtract(const Duration(minutes: 59)),
        now: now,
      ),
      '59分钟前',
    );
    // 时钟偏差：比「现在」还晚的时间按刚刚处理
    expect(
      formatRelativeTime(zh, now.add(const Duration(minutes: 3)), now: now),
      '刚刚',
    );
  });

  test('今日 / 昨日层：按本地日历判断，只显示时分', () {
    expect(
      formatRelativeTime(zh, DateTime(2026, 10, 15, 9, 15), now: now),
      '今天 09:15',
    );
    expect(
      formatRelativeTime(zh, DateTime(2026, 10, 14, 9, 15), now: now),
      '昨天 09:15',
    );
    // 超过 24 小时但仍在昨天（凌晨的时间点）也走「昨天」
    expect(
      formatRelativeTime(
        zh,
        DateTime(2026, 10, 14, 0, 30),
        now: DateTime(2026, 10, 15, 1, 0),
      ),
      '昨天 00:30',
    );
  });

  test('远期层：同年只到日期，跨年带年份', () {
    expect(
      formatRelativeTime(zh, DateTime(2026, 10, 13, 23, 59), now: now),
      '10月13日',
    );
    expect(
      formatRelativeTime(zh, DateTime(2025, 10, 15, 8, 0), now: now),
      '2025年10月15日',
    );
  });

  test('英文文案', () {
    expect(
      formatRelativeTime(
        en,
        now.subtract(const Duration(seconds: 20)),
        now: now,
      ),
      'Just now',
    );
    expect(
      formatRelativeTime(
        en,
        now.subtract(const Duration(minutes: 5)),
        now: now,
      ),
      '5 min ago',
    );
    expect(
      formatRelativeTime(en, DateTime(2026, 10, 15, 9, 15), now: now),
      'Today 09:15',
    );
    expect(
      formatRelativeTime(en, DateTime(2026, 10, 14, 9, 15), now: now),
      'Yesterday 09:15',
    );
    expect(formatRelativeTime(en, DateTime(2026, 10, 13), now: now), '10/13');
    expect(
      formatRelativeTime(en, DateTime(2025, 10, 15), now: now),
      '2025/10/15',
    );
  });
}
