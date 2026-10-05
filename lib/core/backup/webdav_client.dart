import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../app_permissions.dart';

/// 是否是局域网 / 链路本地地址：这些地址在 Android 17（targetSdk 37）起
/// 需要「本地网络」运行时权限，公网地址不受影响。
///
/// 只按字面判断，不做 DNS 解析：`.local` 之类的名字按局域网处理，
/// 其余主机名（域名）交给系统按公网处理。
bool isLocalNetworkHost(String host) {
  final value = host.trim().toLowerCase();
  if (value.isEmpty) return false;
  if (value == 'localhost' || value.endsWith('.local')) return true;
  final address = InternetAddress.tryParse(value);
  if (address == null) return false;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    if (bytes.length != 16) return false;
    // fe80::/10 链路本地；fc00::/7 唯一本地地址
    return (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
        (bytes[0] & 0xfe) == 0xfc;
  }
  if (bytes.length != 4) return false;
  final a = bytes[0];
  final b = bytes[1];
  return a == 10 || // 10.0.0.0/8
      (a == 172 && b >= 16 && b <= 31) || // 172.16.0.0/12
      (a == 192 && b == 168) || // 192.168.0.0/16
      (a == 169 && b == 254); // 169.254.0.0/16 链路本地
}

/// 备份/恢复失败：message 可以直接展示给用户。
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// WebDAV 目录里的一个文件。
class WebdavEntry {
  const WebdavEntry({
    required this.name,
    required this.href,
    this.size = 0,
    this.modified,
  });

  final String name;
  final String href;
  final int size;
  final DateTime? modified;
}

/// 极简 WebDAV 客户端：PROPFIND 列目录、PUT 上传、GET 下载、DELETE 删除。
class WebdavClient {
  WebdavClient({
    required String url,
    this.username = '',
    this.password = '',
    Dio? dio,
  }) : baseUri = normalizeBase(url),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 60),
               sendTimeout: const Duration(seconds: 60),
             ),
           );

  final Uri baseUri;
  final String username;
  final String password;
  final Dio _dio;

  static Uri normalizeBase(String url) {
    var value = url.trim();
    if (value.isEmpty) throw const BackupException('WebDAV 地址为空');
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    if (!value.endsWith('/')) value = '$value/';
    return Uri.parse(value);
  }

  Map<String, String> get _headers => {
    if (username.isNotEmpty)
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  /// Android 17（targetSdk 37）起访问局域网需要「本地网络」权限：
  /// 只对局域网地址请求，公网 WebDAV 保持原样。
  Future<void> ensureLocalNetworkPermission() async {
    if (!isLocalNetworkHost(baseUri.host)) return;
    final granted = await AppPermissions.instance.requestLocalNetwork();
    if (!granted) {
      throw const BackupException(
        '访问局域网内的 WebDAV 需要「本地网络」权限：'
        '请在系统弹窗中允许，或到系统设置 → 应用 → 蓝云 → 权限 中开启后重试',
      );
    }
  }

  Uri _fileUri(String name) => baseUri.resolve(name);

  Future<void> check() => _guard(() async {
    final response = await _request(
      'PROPFIND',
      baseUri,
      headers: const {'Depth': '0'},
      plain: true,
    );
    _ensureOk(response, '连接失败');
  });

  Future<List<WebdavEntry>> list() => _guard(() async {
    final response = await _request(
      'PROPFIND',
      baseUri,
      headers: const {'Depth': '1'},
      plain: true,
    );
    _ensureOk(response, '读取云端目录失败');
    return parsePropfind('${response.data}', baseUri);
  });

  Future<void> upload(String name, String content) => _guard(() async {
    final response = await _dio.putUri(
      _fileUri(name),
      data: content,
      options: Options(
        headers: {
          ..._headers,
          'Content-Type': 'application/json; charset=utf-8',
        },
      ),
    );
    _ensureOk(response, '上传失败');
  });

  Future<String> download(String name) => _guard(() async {
    final response = await _dio.getUri<String>(
      _fileUri(name),
      options: Options(headers: _headers, responseType: ResponseType.plain),
    );
    _ensureOk(response, '下载失败');
    return '${response.data}';
  });

  Future<void> delete(String name) => _guard(() async {
    final response = await _dio.deleteUri(
      _fileUri(name),
      options: Options(headers: _headers),
    );
    _ensureOk(response, '删除失败');
  });

  Future<Response<dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    bool plain = false,
  }) {
    return _dio.requestUri<dynamic>(
      uri,
      options: Options(
        method: method,
        headers: {..._headers, ...?headers},
        responseType: plain ? ResponseType.plain : ResponseType.json,
      ),
    );
  }

  void _ensureOk(Response<dynamic> response, String action) {
    final code = response.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    throw BackupException('$action（HTTP $code）');
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      await ensureLocalNetworkPermission();
      return await run();
    } on BackupException {
      rethrow;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw const BackupException('认证失败，请检查用户名与密码');
      }
      if (code == 404) {
        throw const BackupException('地址不存在（404），请检查服务器地址');
      }
      if (code != null) throw BackupException('请求失败（HTTP $code）');
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw const BackupException('连接超时');
        case DioExceptionType.connectionError:
          throw const BackupException('无法连接服务器，请检查地址与网络');
        default:
          throw BackupException('网络错误：${e.message ?? e.type.name}');
      }
    } catch (e) {
      throw BackupException('$e');
    }
  }
}

/// 解析 PROPFIND 响应（不引入 XML 依赖，兼容各种命名空间前缀）。
List<WebdavEntry> parsePropfind(String xml, Uri base) {
  final entries = <WebdavEntry>[];
  final responseRe = RegExp(
    r'<(?:[A-Za-z0-9_.-]+:)?response\b[^>]*>(.*?)</(?:[A-Za-z0-9_.-]+:)?response>',
    caseSensitive: false,
    dotAll: true,
  );
  final hrefRe = RegExp(
    r'<(?:[A-Za-z0-9_.-]+:)?href\b[^>]*>(.*?)</(?:[A-Za-z0-9_.-]+:)?href>',
    caseSensitive: false,
    dotAll: true,
  );
  final lengthRe = RegExp(
    r'<(?:[A-Za-z0-9_.-]+:)?getcontentlength\b[^>]*>(\d+)<',
    caseSensitive: false,
  );
  final modifiedRe = RegExp(
    r'<(?:[A-Za-z0-9_.-]+:)?getlastmodified\b[^>]*>(.*?)<',
    caseSensitive: false,
    dotAll: true,
  );
  for (final block in responseRe.allMatches(xml)) {
    final body = block.group(1) ?? '';
    final href = hrefRe.firstMatch(body)?.group(1)?.trim();
    if (href == null || href.isEmpty) continue;
    final raw = _unescapeXml(href);
    final path = Uri.decodeComponent(raw);
    // 目录（以 / 结尾）本身不作为备份文件
    if (path.endsWith('/')) continue;
    final name = path.substring(path.lastIndexOf('/') + 1);
    if (name.isEmpty) continue;
    final size = int.tryParse(lengthRe.firstMatch(body)?.group(1) ?? '') ?? 0;
    final modified = _unescapeXml(
      modifiedRe.firstMatch(body)?.group(1)?.trim() ?? '',
    );
    entries.add(
      WebdavEntry(
        name: name,
        href: raw,
        size: size,
        modified: _parseHttpDate(modified),
      ),
    );
  }
  return entries;
}

String _unescapeXml(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

DateTime? _parseHttpDate(String value) {
  if (value.isEmpty) return null;
  try {
    return HttpDate.parse(value);
  } catch (_) {
    return null;
  }
}
