import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/data/settings_store.dart';
import 'package:lancloud/core/update/changelog.dart';
import 'package:lancloud/core/update/release_info.dart';
import 'package:lancloud/core/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 构造一条 Release 记录：tag 带 v 前缀（与发布脚本一致），预发布标记按
/// 版本名推导（与 tools/release/publish.ps1 的预发布判定同一口径）。
ReleaseInfo rel(
  String version, {
  String body = '',
  List<ReleaseAsset> assets = const [],
}) => ReleaseInfo(
  tag: 'v$version',
  version: version,
  body: body,
  htmlUrl: 'https://github.com/Tgaisen/LanCloud/releases/tag/v$version',
  prerelease: isPrereleaseVersion(version),
  draft: false,
  publishedAt: DateTime(2026, 1, 1),
  assets: assets,
);

DioException httpError(int status) => DioException(
  requestOptions: RequestOptions(path: '/releases'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/releases'),
    statusCode: status,
  ),
);

DioException networkError() => DioException(
  requestOptions: RequestOptions(path: '/releases'),
  type: DioExceptionType.unknown,
  error: const SocketException('unreachable'),
);

Future<UpdateService> boundService({
  String channel = 'beta',
  bool autoCheck = true,
}) async {
  final settings = SettingsStore()
    ..updateChannel = channel
    ..updateAutoCheck = autoCheck;
  final service = UpdateService();
  await service.bind(settings);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    UpdateService.debugFetchReleases = null;
    UpdateService.debugNow = DateTime.now;
  });

  tearDown(() {
    UpdateService.debugFetchReleases = null;
    UpdateService.debugNow = DateTime.now;
  });

  group('版本号比较（README 版本号规范）', () {
    test('按 versionCode 分段公式排序', () {
      expect(versionCodeOf('26.1.0-pre.1'), 260100201);
      expect(versionCodeOf('26.1.0-pre.6'), 260100206);
      expect(versionCodeOf('26.1.0'), 260100999);
      expect(versionCodeOf('26.1.0-rc.1'), 260100301);
      expect(versionCodeOf('不合规范'), isNull);

      expect(compareVersionNames('26.1.0', '26.1.0-pre.6'), greaterThan(0));
      expect(
        compareVersionNames('26.1.0-rc.1', '26.1.0-pre.6'),
        greaterThan(0),
      );
      expect(compareVersionNames('26.1.0-pre.6', '26.1.0-pre.10'), lessThan(0));
      expect(
        compareVersionNames('26.1.1-pre.1', '26.1.0'),
        greaterThan(0),
        reason: '下一个热修的预发布比上一个正式版新',
      );
      expect(compareVersionNames('26.1.0-pre.6', '26.1.0-pre.6'), 0);
    });

    test('两个版本名都合规范时才用 versionCode，否则退化成字符串比较', () {
      expect(isPrereleaseVersion('26.1.0-pre.6'), isTrue);
      expect(isPrereleaseVersion('26.1.0'), isFalse);
      expect(compareVersionNames('abc', 'abd'), lessThan(0));
    });
  });

  group('通道过滤', () {
    final releases = [rel('26.1.1-pre.1'), rel('26.1.0'), rel('26.0.5')];

    test('正式版通道只认非预发布', () {
      expect(pickLatest(releases, channel: 'stable')!.version, '26.1.0');
    });

    test('测试版通道取最新（含预发布）', () {
      expect(pickLatest(releases, channel: 'beta')!.version, '26.1.1-pre.1');
    });

    test('通道里一版都没有时返回 null', () {
      expect(pickLatest([rel('26.1.0-pre.6')], channel: 'stable'), isNull);
    });
  });

  group('Release 解析与资产选择', () {
    test('缓存 JSON 往返', () {
      final release = rel(
        '99.0.0',
        body: '## 更新日志\n\n- 内容',
        assets: const [
          ReleaseAsset(
            name: 'LanCloud_android_99.0.0_arm64-v8a.apk',
            url: 'https://example.com/arm64',
            size: 1,
          ),
        ],
      );
      final restored = ReleaseInfo.tryFromJson(jsonEncode(release.toJson()))!;
      expect(restored.tag, 'v99.0.0');
      expect(restored.version, '99.0.0');
      expect(restored.body, release.body);
      expect(restored.assets.single.url, 'https://example.com/arm64');
    });

    test('缓存坏了 / 为空时返回 null', () {
      expect(ReleaseInfo.tryFromJson('{ oops'), isNull);
      expect(ReleaseInfo.tryFromJson('{"tag_name": ""}'), isNull);
    });

    test('Android 按设备 ABI 找安装包，认不出时为空', () {
      final release = rel(
        '99.0.0',
        assets: const [
          ReleaseAsset(
            name: 'LanCloud_android_99.0.0_arm64-v8a.apk',
            url: 'u64',
            size: 1,
          ),
          ReleaseAsset(
            name: 'LanCloud_android_99.0.0_armeabi-v7a.apk',
            url: 'u32',
            size: 1,
          ),
          ReleaseAsset(
            name: 'LanCloud_windows_99.0.0_x64_portable.zip',
            url: 'uw',
            size: 1,
          ),
        ],
      );
      expect(release.androidAssetFor(['arm64-v8a', 'armeabi-v7a'])!.url, 'u64');
      expect(release.androidAssetFor(['armeabi-v7a'])!.url, 'u32');
      expect(release.androidAssetFor(['x86_64']), isNull);
      expect(release.windowsAsset!.url, 'uw');
    });

    test('真实 Release JSON（字段名对齐 GitHub API，取自 v26.1.0-pre.6）', () {
      const apiJson = '''
{
  "tag_name": "v26.1.0-pre.6",
  "prerelease": true,
  "draft": false,
  "body": "## 更新日志\\n\\n- 支持自行开关应用全局动画\\n\\n> Full Changelog: [v26.1.0-pre.5...v26.1.0-pre.6](https://github.com/Tgaisen/LanCloud/compare/v26.1.0-pre.5...v26.1.0-pre.6)\\n\\n## 下载选择\\n\\n- Android：优先 `arm64-v8a`。",
  "html_url": "https://github.com/Tgaisen/LanCloud/releases/tag/v26.1.0-pre.6",
  "published_at": "2026-10-14T15:21:50Z",
  "assets": [
    {
      "name": "LanCloud_android_26.1.0-pre.6_arm64-v8a.apk",
      "size": 26300068,
      "browser_download_url": "https://github.com/Tgaisen/LanCloud/releases/download/v26.1.0-pre.6/LanCloud_android_26.1.0-pre.6_arm64-v8a.apk"
    },
    {
      "name": "LanCloud_windows_26.1.0-pre.6_x64_portable.zip",
      "size": 18938687,
      "browser_download_url": "https://github.com/Tgaisen/LanCloud/releases/download/v26.1.0-pre.6/LanCloud_windows_26.1.0-pre.6_x64_portable.zip"
    }
  ]
}
''';
      final release = ReleaseInfo.tryFromJson(apiJson)!;
      expect(release.version, '26.1.0-pre.6');
      expect(release.prerelease, isTrue);
      expect(release.publishedAt, DateTime.utc(2026, 10, 14, 15, 21, 50));
      expect(
        release.androidAssetFor(['arm64-v8a'])!.name,
        'LanCloud_android_26.1.0-pre.6_arm64-v8a.apk',
      );
      expect(release.windowsAsset!.url, contains('x64_portable.zip'));
      // 真实正文的截取结果：只剩更新日志一行（引用行与「下载选择」小节不显示）
      expect(changelogLines(release.body), ['• 支持自行开关应用全局动画']);
    });
  });

  group('更新日志截取', () {
    test('取「## 更新日志」到下一个小节，跳过引用行', () {
      const body =
          '## 更新日志\n\n'
          '- 第一条\n'
          '- 第二条\n\n'
          '> Full Changelog: [x](https://example.com)\n\n'
          '## 下载选择\n\n'
          '- Android：优先 arm64-v8a';
      expect(changelogLines(body), ['• 第一条', '• 第二条']);
    });

    test('没有标题行时整段显示（以后正文只含列表项也照样能显示）', () {
      expect(changelogLines('- 只有列表\n- 第二条'), ['• 只有列表', '• 第二条']);
    });

    test('剥掉行内标记：加粗与链接', () {
      expect(changelogLines('- **加粗** 与 [链接](https://example.com)'), [
        '• 加粗 与 链接',
      ]);
    });
  });

  group('检测流程', () {
    test('检测成功：有新版本 / 已是最新，12 小时后失效', () async {
      UpdateService.debugFetchReleases = () async => [rel('99.0.0')];
      final service = await boundService();
      expect(service.status, UpdateStatus.idle);

      expect(await service.check(), isTrue);
      expect(service.status, UpdateStatus.available);
      expect(service.hasUpdate, isTrue);
      expect(service.remoteVersion, '99.0.0');

      // 有效期边界：11 小时后仍有效，13 小时后失效
      final checkedAt = service.lastCheckAt!;
      UpdateService.debugNow = () => checkedAt.add(const Duration(hours: 11));
      expect(service.status, UpdateStatus.available);
      UpdateService.debugNow = () => checkedAt.add(const Duration(hours: 13));
      expect(service.status, UpdateStatus.idle);
      expect(service.inValidity, isFalse);
    });

    test('远端与安装版本相同 / 更旧：已是最新版本', () async {
      UpdateService.debugFetchReleases = () async => [rel('1.0.0')];
      final service = await boundService();
      await service.check();
      expect(service.status, UpdateStatus.upToDate);
      expect(service.hasUpdate, isFalse);
    });

    test('通道过滤生效：正式版通道不看预发布', () async {
      UpdateService.debugFetchReleases = () async => [
        rel('99.1.0-pre.1'),
        rel('1.0.0'),
      ];
      final service = await boundService(channel: 'stable');
      await service.check();
      // 正式版通道里最新是 1.0.0（比安装版本旧）→ 已是最新，而不是 99.1.0
      expect(service.remoteVersion, '1.0.0');
      expect(service.status, UpdateStatus.upToDate);
    });

    test('检测失败：状态与错误码，失败不占有效期（重启即回到未检测）', () async {
      UpdateService.debugFetchReleases = () async => throw httpError(403);
      final service = await boundService();
      expect(await service.check(), isFalse);
      expect(service.status, UpdateStatus.failed);
      expect(service.failureCode, 'HTTP 403');

      // 重启（新实例 + 同一份存储）：失败状态只属于本次启动
      final restarted = UpdateService();
      await restarted.bind(SettingsStore());
      expect(restarted.status, UpdateStatus.idle);
      expect(restarted.lastCheckAt, isNull);
    });

    test('跨重启恢复缓存：有效期内不用重新检测', () async {
      UpdateService.debugFetchReleases = () async => [rel('99.0.0')];
      final service = await boundService();
      await service.check();

      final restarted = UpdateService();
      await restarted.bind(SettingsStore());
      expect(restarted.status, UpdateStatus.available);
      expect(restarted.remoteVersion, '99.0.0');
    });

    test('自动检测：有效期内不请求，超过 12 小时才请求', () async {
      var calls = 0;
      UpdateService.debugFetchReleases = () async {
        calls++;
        return [rel('99.0.0')];
      };
      final service = await boundService();
      await service.maybeAutoCheck();
      expect(calls, 1);
      expect(service.status, UpdateStatus.available);

      await service.maybeAutoCheck();
      expect(calls, 1, reason: '有效期内不重复请求');

      final checkedAt = service.lastCheckAt!;
      UpdateService.debugNow = () => checkedAt.add(const Duration(hours: 13));
      await service.maybeAutoCheck();
      expect(calls, 2);
    });

    test('自动检测：关掉开关后不请求', () async {
      var calls = 0;
      UpdateService.debugFetchReleases = () async {
        calls++;
        return [rel('99.0.0')];
      };
      final service = await boundService(autoCheck: false);
      await service.maybeAutoCheck();
      expect(calls, 0);
    });

    test('自动检测失败后 1 小时内不重试（跨重启也生效）', () async {
      var calls = 0;
      UpdateService.debugFetchReleases = () async {
        calls++;
        throw networkError();
      };
      final service = await boundService();
      await service.maybeAutoCheck();
      expect(calls, 1);
      expect(service.status, UpdateStatus.failed);
      expect(service.lastCheckAt, isNull, reason: '失败不写入检测成功时间');

      // 半小时后重启：还在冷却里，不请求
      UpdateService.debugNow = () =>
          DateTime.now().add(const Duration(minutes: 30));
      final restarted = UpdateService();
      await restarted.bind(SettingsStore());
      await restarted.maybeAutoCheck();
      expect(calls, 1);

      // 超过冷却：再自动检测一次
      UpdateService.debugNow = () =>
          DateTime.now().add(const Duration(hours: 2));
      await restarted.maybeAutoCheck();
      expect(calls, 2);
    });

    test('切换通道：清掉旧结果；开着自动检查时立即重检', () async {
      var calls = 0;
      UpdateService.debugFetchReleases = () async {
        calls++;
        return [rel('99.0.0')];
      };
      final service = await boundService(autoCheck: false);
      await service.check();
      expect(service.status, UpdateStatus.available);

      await service.onChannelChanged();
      expect(service.status, UpdateStatus.idle);
      expect(service.lastCheckAt, isNull);
      expect(calls, 1, reason: '关着自动检查就不自动重检');

      // 旧结果也不会从磁盘复活
      final restarted = UpdateService();
      await restarted.bind(SettingsStore());
      expect(restarted.status, UpdateStatus.idle);
      expect(restarted.remoteVersion, isNull);
    });

    test('切换通道且开着自动检查：立即重新检测', () async {
      var calls = 0;
      UpdateService.debugFetchReleases = () async {
        calls++;
        return [rel('99.0.0')];
      };
      final service = await boundService();
      await service.onChannelChanged();
      // onChannelChanged 里的重检是 fire-and-forget，等它跑完
      for (var i = 0; i < 100 && (calls == 0 || service.checking); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(calls, 1);
      expect(service.status, UpdateStatus.available);
    });

    test('iOS 等没有产物的平台：不检测、不自动请求', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var calls = 0;
      UpdateService.debugFetchReleases = () async {
        calls++;
        return [rel('99.0.0')];
      };
      final service = await boundService();
      expect(service.supported, isFalse);
      await service.maybeAutoCheck();
      expect(await service.check(), isFalse);
      expect(calls, 0);
      expect(service.status, UpdateStatus.idle);
    });

    test('失败原因 → 连接错误码', () {
      expect(
        failureCodeOf(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        'TIMEOUT',
      );
      expect(failureCodeOf(httpError(404)), 'HTTP 404');
      expect(failureCodeOf(networkError()), 'NETWORK');
      expect(failureCodeOf(const FormatException('bad json')), 'PARSE');
      expect(failureCodeOf(StateError('boom')), 'UNKNOWN');
    });
  });
}
