import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/search_options.dart';

void main() {
  group('SearchQuery', () {
    test('默认大小写不敏感且按名称子串匹配', () {
      final query = SearchQuery.parse('report', SearchOptions.disabled);

      expect(query.matches('Quarterly REPORT.pdf'), isTrue);
      expect(query.matches('Quarterly-summary.pdf'), isFalse);
    });

    test('区分大小写时只匹配大小写完全相同的内容', () {
      final query = SearchQuery.parse(
        'Report',
        const SearchOptions(matchCase: true),
      );

      expect(query.matches('Report-final.pdf'), isTrue);
      expect(query.matches('report-final.pdf'), isFalse);
    });

    test('全字匹配支持拉丁字符、中文和标点边界', () {
      final latin = SearchQuery.parse(
        'report',
        const SearchOptions(wholeWord: true),
      );
      final chinese = SearchQuery.parse(
        '报告',
        const SearchOptions(wholeWord: true),
      );

      expect(latin.matches('report-final.pdf'), isTrue);
      expect(latin.matches('final-report'), isTrue);
      expect(latin.matches('reporting.pdf'), isFalse);
      expect(chinese.matches('季度-报告-2026.pdf'), isTrue);
      expect(chinese.matches('季度报告2026.pdf'), isFalse);
    });

    test('正则表达式支持大小写和全字匹配组合', () {
      final query = SearchQuery.parse(
        'foo|bar',
        const SearchOptions(matchCase: true, wholeWord: true, regex: true),
      );

      expect(query.matches('bar-final.pdf'), isTrue);
      expect(query.matches('BAR-final.pdf'), isFalse);
      expect(query.matches('foobar.pdf'), isFalse);
    });

    test('无效正则返回无匹配且不抛异常', () {
      final query = SearchQuery.parse('[', const SearchOptions(regex: true));

      expect(query.isValid, isFalse);
      expect(query.matches('任意名称'), isFalse);
    });

    test('空白查询和选项集合转换保持稳定', () {
      final query = SearchQuery.parse('   ', SearchOptions.disabled);
      final options = SearchOptions.fromEnabled({
        SearchOption.matchCase,
        SearchOption.regex,
      });

      expect(query.matches('任意名称'), isTrue);
      expect(options.matchCase, isTrue);
      expect(options.wholeWord, isFalse);
      expect(options.regex, isTrue);
      expect(options.enabled, {SearchOption.matchCase, SearchOption.regex});
    });
  });
}
