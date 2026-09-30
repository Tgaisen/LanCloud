import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'acw_sc_v2.dart';
import 'models.dart';

const kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

class LanzouException implements Exception {
  const LanzouException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NeedPasswordException extends LanzouException {
  const NeedPasswordException() : super('该分享需要提取码');
}

class LanzouClient {
  /// 全局请求间隔，避免触发风控（可在设置里调整）。
  static Duration requestInterval = const Duration(milliseconds: 300);

  LanzouClient({required this.uid}) {
    dio = Dio(BaseOptions(
      headers: {
        'User-Agent': userAgent.isEmpty ? kUserAgent : userAgent,
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': 'https://pc.woozooo.com/mydisk.php',
      },
      validateStatus: (s) => s != null && s < 500,
      receiveTimeout: const Duration(seconds: 60),
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (requestInterval > Duration.zero) {
          await Future.delayed(requestInterval);
        }
        final cookie = _cookieHeaderFor(options.uri.host);
        if (cookie.isNotEmpty) options.headers['Cookie'] = cookie;
        handler.next(options);
      },
      onResponse: (response, handler) {
        _storeCookies(response.requestOptions.uri.host, response.headers);
        handler.next(response);
      },
    ));
  }

  /// 网盘接口域名，可在设置里临时切换（连接异常时尝试另一个）。
  static String apiBase = 'https://pc.woozooo.com';

  /// 自定义 User-Agent，留空表示使用内置默认值。
  static String userAgent = '';
  static const uploadBase = 'https://up.woozooo.com';

  final String uid;
  late final Dio dio;

  /// host -> (cookie name -> value)
  final Map<String, Map<String, String>> _jar = {};

  void setCookieHeader(String raw) {
    final map = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) {
        map[part.substring(0, i).trim()] = part.substring(i + 1).trim();
      }
    }
    _jar.putIfAbsent('woozooo.com', () => {}).addAll(map);
  }

  String _cookieHeaderFor(String host) {
    final merged = <String, String>{};
    if (host.endsWith('woozooo.com')) {
      merged.addAll(_jar['woozooo.com'] ?? const {});
    }
    merged.addAll(_jar[host] ?? const {});
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _storeCookies(String host, Headers headers) {
    final dynamic raw = headers['set-cookie'];
    final list = <String>[];
    if (raw is List) {
      for (final item in raw) {
        list.add('$item');
      }
    } else if (raw is String) {
      list.add(raw);
    }
    if (list.isEmpty) return;
    final key = host.endsWith('woozooo.com') ? 'woozooo.com' : host;
    final jar = _jar.putIfAbsent(key, () => {});
    for (final c in list) {
      final first = c.split(';').first;
      final i = first.indexOf('=');
      if (i > 0) jar[first.substring(0, i).trim()] = first.substring(i + 1).trim();
    }
  }

  Options _options({bool followRedirects = true, String? referer}) => Options(
        responseType: ResponseType.plain,
        contentType: 'application/x-www-form-urlencoded',
        receiveTimeout: const Duration(seconds: 25),
        followRedirects: followRedirects,
        validateStatus: (s) => s != null && s < 500,
        headers: referer == null ? null : {'Referer': referer},
      );

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    final text = '$data'.trim();
    final json = jsonDecode(text);
    if (json is Map) return json.cast<String, dynamic>();
    throw const LanzouException('接口返回格式异常');
  }

  String? _match(String source, List<String> patterns) {
    for (final p in patterns) {
      final m = RegExp(p, dotAll: true).firstMatch(source);
      if (m != null && m.groupCount >= 1) return m.group(1);
    }
    return null;
  }

  String _normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    return u;
  }

  // ---------------------------------------------------------------- account

  Future<bool> verify() async {
    try {
      final resp = await dio.post<String>(
        '$apiBase/doupload.php',
        data: {'task': 5, 'folder_id': -1, 'pg': 1},
        options: _options(),
      );
      return '${_asMap(resp.data)['zt']}' == '1';
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------- file lists

  /// 取文件列表的某一页（info 为该页条数，0 表示没有更多）。
  Future<({List<LzFile> files, bool hasMore})> listFilesPage(
    String folderId,
    int page,
  ) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 5, 'folder_id': folderId, 'pg': page},
      options: _options(),
    );
    final map = _asMap(resp.data);
    final files = <LzFile>[];
    final text = map['text'];
    if (text is List) {
      for (final item in text) {
        if (item is Map) files.add(LzFile.fromJson(item.cast<String, dynamic>()));
      }
    }
    final info = int.tryParse('${map['info']}') ?? 0;
    return (files: files, hasMore: info != 0 && files.isNotEmpty);
  }

  Future<List<LzFile>> listFiles(String folderId) async {
    final all = <LzFile>[];
    var page = 1;
    while (page <= 60) {
      final result = await listFilesPage(folderId, page);
      all.addAll(result.files);
      if (!result.hasMore) break;
      page += 1;
    }
    return all;
  }

  Future<({List<LzFolder> folders, List<PathNode> path})> listFolders(
    String folderId,
  ) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      queryParameters: {'uid': uid},
      data: {'task': 47, 'folder_id': folderId},
      options: _options(),
    );
    final map = _asMap(resp.data);
    final folders = <LzFolder>[];
    final text = map['text'];
    if (text is List) {
      for (final item in text) {
        if (item is Map) folders.add(LzFolder.fromJson(item.cast<String, dynamic>()));
      }
    }
    final path = <PathNode>[];
    final info = map['info'];
    if (info is List) {
      for (final item in info) {
        if (item is Map && item['folderid'] != null && item['name'] != null) {
          path.add(PathNode(id: '${item['folderid']}', name: '${item['name']}'));
        }
      }
    }
    return (folders: folders, path: path);
  }

  Future<void> mkdir(String parentId, String name, {String desc = ''}) async {
    final safe = name.replaceAll(' ', '_').replaceAll(RegExp(r'''[\$%^!*<>)(+=`'"/:;,?]'''), '');
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {
        'task': 2,
        'parent_id': parentId,
        'folder_name': safe,
        'folder_description': desc,
      },
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException('新建文件夹失败');
    }
  }

  Future<void> deleteItem({required String id, required bool isFile}) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: isFile ? {'task': 6, 'file_id': id} : {'task': 3, 'folder_id': id},
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException('删除失败');
    }
  }

  /// 修改文件简介（task 11）。
  /// 网页版文件夹信息页：直接读取该文件夹的统计信息。
  /// 解析失败返回 null，由调用方回退到遍历统计。
  Future<
      ({
        String size,
        int count,
        String name,
        String desc,
        String url,
      })?> folderStats(String folderId) async {
    try {
      final resp = await dio.get<String>(
        'https://up.woozooo.com/myfile.php',
        queryParameters: {'item': '3', 'folder_id': folderId, 'v2': ''},
        options: _options(referer: '$apiBase/mydisk.php'),
      );
      final html = resp.data ?? '';
      if (html.isEmpty || html.contains('网盘用户登录')) return null;
      final size = RegExp(
        r'<div class="folsha2">大小<div class="folsha3">([^<]*)</div>',
      ).firstMatch(html)?.group(1)?.trim() ??
          '';
      final count = int.tryParse(
            RegExp(r'<div class="folsha2">文件数<div class="folsha3">(\d+)</div>')
                    .firstMatch(html)
                    ?.group(1) ??
                '',
          ) ??
          0;
      final name = RegExp(r'id="foldertxt"[^>]*value="([^"]*)"')
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '';
      final desc = RegExp(r'id="folderinfo"[^>]*value="([^"]*)"')
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '';
      final url = RegExp(r'class="f_pwdurl"[^>]*>(https?://[^<]+)</div>')
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '';
      if (size.isEmpty && count == 0) return null;
      return (size: size, count: count, name: name, desc: desc, url: url);
    } catch (_) {
      return null;
    }
  }

  /// 读取文件简介（task 12 的 info 字段）。
  Future<String> fileDesc(String fileId) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 12, 'file_id': fileId},
      options: _options(),
    );
    final map = _asMap(resp.data);
    return '${map['info'] ?? ''}'.trim();
  }

  Future<void> setDesc(String fileId, String desc) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 11, 'file_id': fileId, 'desc': desc},
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException('修改简介失败');
    }
  }

  /// 设置文件访问密码（task 23，免费账号只能设置不能关闭）。
  Future<void> setPasswd(String fileId, String pwd) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {
        'task': 23,
        'file_id': fileId,
        'shows': pwd.isEmpty ? 0 : 1,
        'shownames': pwd,
      },
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException('设置访问密码失败');
    }
  }

  // ----------------------------------------------------------------- upload

  Future<void> uploadFile({
    required String name,
    required String folderId,
    String? path,
    Stream<List<int>> Function()? streamFactory,
    int? size,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final length = size ?? (path != null ? await File(path).length() : 0);
    final MultipartFile part;
    if (path != null) {
      part = await MultipartFile.fromFile(path, filename: name);
    } else if (streamFactory != null) {
      part = MultipartFile.fromStream(streamFactory, length, filename: name);
    } else {
      throw const LanzouException('没有可上传的文件内容');
    }
    final form = FormData.fromMap({
      'task': '1',
      'vie': '2',
      've': '2',
      'id': 'WU_FILE_0',
      'folder_id_bb_n': folderId,
      'name': name,
      'size': '$length',
      'type': 'application/octet-stream',
      'lastModifiedDate': DateTime.now().toUtc().toString(),
      'upload_file': part,
    });
    final resp = await dio.post<String>(
      '$uploadBase/html5up.php',
      data: form,
      cancelToken: cancelToken,
      onSendProgress: (sent, total) => onProgress?.call(sent, total),
      options: Options(
        headers: {'Referer': '$uploadBase/mydisk.php'},
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(hours: 2),
        receiveTimeout: const Duration(minutes: 10),
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final map = _asMap(resp.data);
    if ('${map['zt']}' != '1') {
      throw LanzouException('上传失败：${map['info'] ?? '未知错误'}');
    }
  }

  // ------------------------------------------------------------------ share

  Future<ShareInfo> shareInfoOfFile(String fileId) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 22, 'file_id': fileId},
      options: _options(),
    );
    final info = (_asMap(resp.data)['info'] as Map).cast<String, dynamic>();
    final fId = '${info['f_id'] ?? ''}';
    if (fId.isEmpty || fId == 'i') {
      throw const LanzouException('无法获取该文件的分享信息');
    }
    var name = '${info['name'] ?? ''}';
    var desc = '';
    try {
      final extra = _asMap((await dio.post<String>(
        '$apiBase/doupload.php',
        data: {'task': 12, 'file_id': fileId},
        options: _options(),
      ))
          .data);
      name = '${extra['text'] ?? name}';
      desc = '${extra['info'] ?? ''}';
    } catch (_) {}
    return ShareInfo(
      url: '${info['is_newd']}/$fId',
      pwd: '${info['onof']}' == '1' ? '${info['pwd']}' : '',
      isFile: true,
      name: name,
      desc: desc,
    );
  }

  Future<ShareInfo> shareInfoOfFolder(String folderId) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 18, 'folder_id': folderId},
      options: _options(),
    );
    final info = (_asMap(resp.data)['info'] as Map).cast<String, dynamic>();
    return ShareInfo(
      url: '${info['new_url'] ?? ''}',
      pwd: '${info['onof']}' == '1' ? '${info['pwd']}' : '',
      isFile: false,
      name: '${info['name'] ?? ''}',
      desc: '${info['des'] ?? ''}',
    );
  }

  Future<String> fetchSharePage(String url) async {
    var resp = await dio.get<String>(url, options: _options(referer: url));
    var html = resp.data ?? '';
    if (html.contains('acw_sc__v2')) {
      final token = calcAcwScV2(html);
      if (token.isNotEmpty) {
        _jar.putIfAbsent(Uri.parse(url).host, () => {})['acw_sc__v2'] = token;
        resp = await dio.get<String>(url, options: _options(referer: url));
        html = resp.data ?? '';
      }
    }
    return html;
  }

  String _absoluteUrl(String base, String scheme, String path) {
    if (path.startsWith('http')) return path;
    if (path.startsWith('//')) return '$scheme:$path';
    return '$base$path';
  }

  /// 解析 JS 值：字面量直接返回；变量名则查找它的 var 定义。
  String _resolveJsValue(String html, String token) {
    final t = token.trim().replaceAll(RegExp(r',$'), '').trim();
    if (t.isEmpty) return '';
    final literal = RegExp(r'''^['"](.*)['"]$''', dotAll: true).firstMatch(t);
    if (literal != null) return literal.group(1)!;
    if (!RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(t)) return '';
    final def = RegExp('var\\s+${RegExp.escape(t)}\\s*=\\s*([^;]+);').firstMatch(html);
    if (def == null) return '';
    return def.group(1)!.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  }

  /// dom + /file/ + path 拿 302，Location 就是真实直链。
  Future<String?> _followDownloadRedirect(
    String dom,
    String path,
    String referer,
  ) async {
    final target = path.startsWith('http')
        ? path
        : '$dom/file/${path.replaceAll(RegExp(r'^/+'), '')}';
    if (!target.startsWith('http')) return null;
    final head = await dio.get<String>(
      target,
      options: _options(followRedirects: false, referer: referer),
    );
    final location = head.headers.value('location');
    return (location != null && location.isNotEmpty) ? location : null;
  }

  /// 新版流程：iframe 页面里的参数通过 ajaxfile.php 换取直链。
  Future<String?> _resolveViaAjaxFile(
    String pageHtml,
    String pageUrl,
    String referer,
    String pwd,
  ) async {
    final endpointRaw = _match(pageHtml, [
          r'''url\s*:\s*['"]([^'"]*ajaxfile\.php[^'"]*)['"]''',
          r'''var\s+domain1\s*=\s*['"]([^'"]+)['"]''',
        ]) ??
        _match(pageHtml, [r'''url\s*:\s*['"]([^'"]+)['"]''']);
    if (endpointRaw == null) return null;
    final pageUri = Uri.parse(pageUrl);
    final endpoint = _absoluteUrl(
      '${pageUri.scheme}://${pageUri.host}',
      pageUri.scheme,
      endpointRaw,
    );

    final block =
        RegExp(r'data\s*:\s*\{([^}]*)\}', dotAll: true).firstMatch(pageHtml)?.group(1) ??
            '';
    final fields = <String, String>{};
    for (final m
        in RegExp(r"""['"]?(\w+)['"]?\s*:\s*([^,}]+)""").allMatches(block)) {
      fields[m.group(1)!] = _resolveJsValue(pageHtml, m.group(2)!);
    }
    final sign = fields['sign'] ?? '';
    if (sign.isEmpty) return null;

    final kdCandidates = <String>{
      fields['kd'] ?? '',
      for (final m in RegExp(r'var\s+kdns\s*=\s*([^;]+);').allMatches(pageHtml))
        m.group(1)!.trim(),
      '1',
      '0',
    }.where((e) => e.isNotEmpty).toList();

    for (final kd in kdCandidates) {
      final resp = await dio.post<String>(
        endpoint,
        data: <String, dynamic>{
          'action': 'downprocess',
          'websignkey': fields['websignkey'] ?? '',
          'signs': fields['signs'] ?? '',
          'sign': sign,
          'websign': fields['websign'] ?? '',
          'kd': kd,
          'ves': fields['ves'] ?? '1',
        },
        options: _options(referer: pageUrl),
      );
      final map = _asMap(resp.data);
      if ('${map['zt']}' == '1') {
        final dom = '${map['dom'] ?? ''}';
        final path = '${map['url'] ?? ''}';
        if (path.startsWith('http')) return path;
        if (path.startsWith('?') && dom.isNotEmpty) {
          // 这个链接本身就是直链；先用 Range 请求过一次人机校验，
          // 把 acw_sc__v2 Cookie 存到该 CDN 域名下，下载时才能拿到文件本体。
          final directUrl = '$dom/file/$path';
          await _primeDirectUrl(directUrl);
          return directUrl;
        }
        if (dom.isNotEmpty && path.isNotEmpty) {
          return _followDownloadRedirect(dom, path, pageUrl);
        }
      }
      final info = '${map['inf'] ?? map['info'] ?? ''}';
      if (info.contains('密码')) break;
    }
    return null;
  }

  /// 轻量访问一次直链，必要时解出 acw_sc__v2 并记住 Cookie。
  Future<void> _primeDirectUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final resp = await dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Range': 'bytes=0-0'},
        ),
      );
      final body = resp.data ?? '';
      if (body.contains('acw_sc__v2')) {
        final token = calcAcwScV2(body);
        if (token.isNotEmpty) {
          _jar.putIfAbsent(uri.host, () => {})['acw_sc__v2'] = token;
        }
      }
    } catch (_) {
      // 预热失败不阻塞解析，下载阶段失败会有明确提示
    }
  }

  /// 个性化域名容易超时/被风控，这里给出同后缀主域与其他镜像作为回退。
  List<String> _shareUrlCandidates(String shareUrl) {
    final url = _normalizeUrl(shareUrl);
    final uri = Uri.parse(url);
    final list = <String>[url];
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.query.isEmpty ? '' : '?${uri.query}';
    final family = RegExp(r'\.lanzou([a-z])\.com$').firstMatch(uri.host);
    final candidates = <String>[
      if (family != null) 'www.lanzou${family.group(1)}.com',
      'www.lanzoue.com',
      'www.lanzoui.com',
      'www.lanzouw.com',
      'www.lanzouf.com',
    ];
    for (final host in candidates) {
      if (host == uri.host) continue;
      final candidate = '${uri.scheme}://$host$path$query';
      if (!list.contains(candidate)) list.add(candidate);
    }
    return list;
  }

  Future<DirectFile> resolveFileShare(String shareUrl, {String pwd = ''}) async {
    Object? lastError;
    for (final candidate in _shareUrlCandidates(shareUrl)) {
      try {
        return await _resolveFileShareOn(candidate, pwd);
      } on NeedPasswordException {
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError is LanzouException
        ? lastError
        : LanzouException('解析分享失败：$lastError');
  }

  Future<DirectFile> _resolveFileShareOn(String url, String pwd) async {
    final uri = Uri.parse(url);
    final base = '${uri.scheme}://${uri.host}';
    final html = await fetchSharePage(url);
    if (html.contains('文件不存') || html.contains('文件取消')) {
      throw const LanzouException('文件不存在或已取消分享');
    }
    final needPwd = html.contains('id="pwdload"') || html.contains('id="passwddiv"');
    if (needPwd && pwd.isEmpty) throw const NeedPasswordException();

    var name = _match(html, [
          r'<title>(.+?) - 蓝奏云</title>',
          r'<div class="filethetext".+?>([^<>]+?)</div>',
        ]) ??
        url.split('/').last;
    final size =
        (_match(html, [r'大小.+?(\d[\d.,]+\s?[BKM]?)<']) ?? '').replaceAll(',', '');

    // 新版流程：分享页 -> iframe -> ajaxfile.php
    final iframeRaw = RegExp(r'<iframe.*?src="(.+?)"').firstMatch(html)?.group(1);
    var legacyHtml = html;
    String? iframeUrl;
    if (iframeRaw != null) {
      iframeUrl = _absoluteUrl(base, uri.scheme, iframeRaw);
      final iframeHtml = await fetchSharePage(iframeUrl);
      legacyHtml = iframeHtml;
      final frameTitle = _match(iframeHtml, [r'<title>(.+?)</title>']);
      if (frameTitle != null && frameTitle.trim().isNotEmpty) {
        name = frameTitle.trim();
      }
      final direct = await _resolveViaAjaxFile(iframeHtml, iframeUrl, url, pwd);
      if (direct != null) {
        return DirectFile(name: name, url: direct, size: size);
      }
    }

    // 旧版流程回退：ajaxm.php
    String? sign;
    if (needPwd) {
      final pwdSign = RegExp(r'sign=(\w+?)&').firstMatch(html)?.group(1);
      if (pwdSign == null) throw const LanzouException('提取码参数解析失败');
      sign = pwdSign;
    } else {
      var rawSign = RegExp(r"'sign':(.+?),").firstMatch(legacyHtml)?.group(1) ?? '';
      rawSign = rawSign.replaceAll("'", '').trim();
      if (rawSign.isNotEmpty && rawSign.length < 20) {
        final resolved = _resolveJsValue(legacyHtml, rawSign);
        if (resolved.isNotEmpty) rawSign = resolved;
      }
      sign = rawSign;
    }
    if (sign.isEmpty) throw const LanzouException('下载参数解析失败');
    final linkResp = await dio.post<String>(
      '$base/ajaxm.php',
      data: {
        'action': 'downprocess',
        'sign': sign,
        'ves': 1,
        if (needPwd) 'p': pwd,
      },
      options: _options(referer: iframeUrl ?? url),
    );
    final link = _asMap(linkResp.data);
    if ('${link['zt']}' != '1') {
      throw LanzouException(
        '获取下载地址失败：${link['inf'] ?? link['info'] ?? link}',
      );
    }
    final dom = '${link['dom'] ?? ''}';
    final path = '${link['url'] ?? ''}';
    final direct = path.startsWith('http')
        ? path
        : await _followDownloadRedirect(dom, path, url);
    if (direct == null || direct.isEmpty) {
      throw const LanzouException('未获取到直链');
    }
    return DirectFile(name: name, url: direct, size: size);
  }

  Future<FolderShareDetail> resolveFolderShare(
    String shareUrl, {
    String pwd = '',
  }) async {
    final url = _normalizeUrl(shareUrl);
    final uri = Uri.parse(url);
    final base = '${uri.scheme}://${uri.host}';
    final html = await fetchSharePage(url);
    if (html.contains('文件不存') || html.contains('文件取消')) {
      throw const LanzouException('文件夹不存在或已取消分享');
    }
    final needPwd = html.contains('id="pwdload"') || html.contains('id="passwddiv"');
    if (needPwd && pwd.isEmpty) throw const NeedPasswordException();
    final lx = _match(html, [r"'lx':'?(\d)'?,"]);
    final t = _match(html, [r"var [0-9a-z]{6} = '(\d{10})';"]);
    final k = _match(html, [r"var [0-9a-z]{6} = '([0-9a-z]{15,})';"]);
    final fid = _match(html, [r"'fid':'?(\d+)'?,"]);
    if (lx == null || t == null || k == null || fid == null) {
      throw const LanzouException('分享页结构解析失败');
    }
    final name = _match(html, [
          r"var.+?='(.+?)';\n.+document.title",
          r'<div class="user-title">(.+?)</div>',
        ]) ??
        '';
    final desc = _match(html, [
          r'id="filename">(.+?)</span>',
          r'<div class="user-radio-\d"></div>(.+?)</div>',
        ]) ??
        '';
    final files = <ShareFileItem>[];
    var page = 1;
    while (page <= 50) {
      if (page >= 2) await Future.delayed(const Duration(milliseconds: 600));
      final resp = await dio.post<String>(
        '$base/filemoreajax.php',
        data: {'lx': lx, 'pg': page, 'k': k, 't': t, 'fid': fid, 'pwd': pwd},
        options: _options(referer: url),
      );
      final map = _asMap(resp.data);
      final zt = '${map['zt']}';
      if (zt == '1') {
        final text = map['text'];
        if (text is List) {
          for (final item in text) {
            if (item is Map) {
              files.add(ShareFileItem(
                name: '${item['name_all'] ?? ''}',
                time: '${item['time'] ?? ''}',
                size: '${item['size'] ?? ''}',
                url: '$base/${item['id']}',
              ));
            }
          }
        }
        page += 1;
        continue;
      }
      if (zt == '2') break;
      if (zt == '3') throw const LanzouException('提取码错误');
      if (zt == '4') continue;
      throw const LanzouException('获取分享文件列表失败');
    }
    final folders = <SubFolder>[];
    for (final m in RegExp(
      r'mbxfolder"><a href="(.+?)".+class="filename">(.+?)<div class="filesize">(.*?)</div>',
      dotAll: true,
    ).allMatches(html)) {
      final href = m.group(1)!;
      folders.add(SubFolder(
        name: m.group(2)!,
        desc: m.group(3)!,
        url: href.startsWith('http') ? href : '$base$href',
      ));
    }
    return FolderShareDetail(name: name, desc: desc, files: files, folders: folders);
  }
}
