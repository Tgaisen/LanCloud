import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../upload_policy.dart';
import 'acw_sc_v2.dart';
import 'models.dart';

const kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const String kFallbackAccountNickname = '用户';

enum LanzouErrorCode {
  passwordRequired,
  wrongPassword,
  invalidResponse,
  createFolderFailed,
  deleteFailed,
  moveFileFailed,
  moveToCurrentFolder,
  moveFolderWithSubfoldersUnsupported,
  readFolderInfoFailed,
  sameTargetFolder,
  updateDescriptionFailed,
  fileNameRequired,
  renameRequiresMembership,
  updateFilePasswordFailed,
  folderNameRequired,
  updateFolderInfoFailed,
  updateFolderPasswordFailed,
  uploadContentMissing,
  uploadFailed,
  fileShareInfoFailed,
  folderShareInfoFailed,
  resolveShareFailed,
  fileShareUnavailable,
  passwordParameterParseFailed,
  downloadParameterParseFailed,
  downloadUrlFailed,
  directLinkMissing,
  folderShareUnavailable,
  sharePageParseFailed,
  shareFileListFailed,
}

class LanzouException implements Exception {
  const LanzouException(this.message, {this.code, this.detail});

  final String message;
  final LanzouErrorCode? code;

  /// 服务端原文或底层异常；有 [code] 时由界面层拼进本地化文案。
  final String? detail;

  @override
  String toString() => message;
}

class NeedPasswordException extends LanzouException {
  const NeedPasswordException()
    : super('该分享需要提取码', code: LanzouErrorCode.passwordRequired);
}

/// 提取码错误：分享需要密码，但填的密码不对。
class WrongPasswordException extends LanzouException {
  const WrongPasswordException()
    : super('提取码错误', code: LanzouErrorCode.wrongPassword);
}

/// Cookie 缺少 ylogin 字段。
class CookieFormatException extends LanzouException {
  const CookieFormatException() : super('未找到 ylogin，请确认复制的是完整 Cookie');
}

/// Cookie 无效或已过期。
class CookieInvalidException extends LanzouException {
  const CookieInvalidException() : super('Cookie 无效或已过期，请重新获取');
}

/// 恢复备份或手动登录时对账号登录态的分层校验结果。
///
/// 网络异常和账号失效必须区分：前者不应把用户引向重新获取 Cookie，
/// 后者也不应阻止用户恢复备份中的其他数据。
enum LoginStateValidation { valid, invalid, networkError, serverError }

class LanzouClient {
  /// 全局请求间隔，避免触发风控（可在设置里调整）。
  static Duration requestInterval = const Duration(milliseconds: 300);

  /// 分享文件夹每页条数：分享页 JS 里是 `data.length < 50` 时隐藏「更多」，
  /// 所以不足 50 条就是最后一页。
  static const int _shareFilesPerPage = 50;

  LanzouClient({required this.uid}) {
    dio = Dio(
      BaseOptions(
        headers: {
          'User-Agent': userAgent.isEmpty ? kUserAgent : userAgent,
          'Accept-Language': 'zh-CN,zh;q=0.9',
          // 默认 Referer 也要跟着「网盘接口域名」设置走
          'Referer': '$apiBase/mydisk.php',
        },
        validateStatus: (s) => s != null && s < 500,
        // 连接阶段也必须限时：否则网络异常（丢包 / 半开连接）时请求会一直挂着，
        // 页面停在加载中、下拉刷新小球也收不回来
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (requestInterval > Duration.zero) {
            await Future<void>.delayed(requestInterval);
          }
          final cookie = _cookieHeaderFor(options.uri.host);
          if (cookie.isNotEmpty) options.headers['Cookie'] = cookie;
          handler.next(options);
        },
        onResponse: (response, handler) {
          _storeCookies(response.requestOptions.uri.host, response.headers);
          handler.next(response);
        },
      ),
    );
  }

  /// 网盘接口域名，可在设置里临时切换（连接异常时尝试另一个）。
  static String apiBase = 'https://pc.woozooo.com';

  /// 自定义 User-Agent，留空表示使用内置默认值。
  static String userAgent = '';

  /// 网页版网盘首页：网页版 / 回收站 / 网页登录这些页面都在当前配置的
  /// 域名下，不走写死的 pc.woozooo.com。
  static String get mydiskUrl => '$apiBase/mydisk.php';

  /// 网页登录地址（与网页版同一个域名）。
  static String get loginUrl => '$apiBase/account.php';

  /// 新版个人中心：昵称、单文件上限和允许上传类型都在这一页。
  static String get accountProfileUrl =>
      '$apiBase/mydisk.php?item=profile&action=mypower';

  /// 上传接口路径（接口名）：html5up.php（默认）/ fileup.php。
  ///
  /// 上传只开放**路径**这一个设置：域名永远跟随「网盘接口域名」
  /// （[apiBase]）；上传以外的场景一律用 [apiBase]，不要碰上传地址。
  static String uploadPath = 'html5up.php';

  /// 上传接口地址：域名始终取 [apiBase]，路径取 [uploadPath] 的最后一段
  /// （设置里只提供 html5up.php / fileup.php；万一存了带域名 / 带斜杠的值，
  /// 也只当路径用）。
  static String get uploadUrl {
    final segment = uploadPath.trim().split('/').last;
    return '$apiBase/${segment.isEmpty ? 'html5up.php' : segment}';
  }

  final String uid;
  late final Dio dio;

  /// 同一个账号客户端在一个接口域名下只抓一次个人中心；登录、启动补资料和
  /// 上传前读取限制会共用这次请求。
  Future<({String? nickname, String level, LanzouUploadPolicy uploadPolicy})>?
  _accountInfoRequest;
  String? _accountInfoRequestBase;
  LanzouUploadPolicy _uploadPolicy = LanzouUploadPolicy.fallback;

  /// 上传筛选使用的最新账号规则；尚未抓到网页信息时使用内置兜底值。
  LanzouUploadPolicy get uploadPolicy => _uploadPolicy;

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
      if (i > 0) {
        jar[first.substring(0, i).trim()] = first.substring(i + 1).trim();
      }
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
    throw const LanzouException(
      '接口返回格式异常',
      code: LanzouErrorCode.invalidResponse,
    );
  }

  Map<String, dynamic> _requireMap(
    Object? value, {
    required String message,
    required LanzouErrorCode code,
  }) {
    if (value is! Map) throw LanzouException(message, code: code);
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw LanzouException(message, code: code);
    }
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

  Future<bool> verify() async =>
      await validateLoginState() == LoginStateValidation.valid;

  /// 校验当前 Cookie 是否仍可登录。
  ///
  /// 与 [verify] 不同，这里不把所有失败都折叠成 `false`，恢复流程可以据此
  /// 区分「Cookie 已失效」「网络不可达」和「服务端异常」。
  Future<LoginStateValidation> validateLoginState() async {
    try {
      final resp = await dio.post<String>(
        '$apiBase/doupload.php',
        data: {'task': 5, 'folder_id': -1, 'pg': 1},
        options: _options(),
      );
      if (resp.statusCode != null && resp.statusCode! >= 500) {
        return LoginStateValidation.serverError;
      }
      return '${_asMap(resp.data)['zt']}' == '1'
          ? LoginStateValidation.valid
          : LoginStateValidation.invalid;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 500) {
        return LoginStateValidation.serverError;
      }
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.connectionError => LoginStateValidation.networkError,
        _ => LoginStateValidation.serverError,
      };
    } catch (_) {
      return LoginStateValidation.serverError;
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
        if (item is Map) {
          files.add(LzFile.fromJson(item.cast<String, dynamic>()));
        }
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
        if (item is Map) {
          folders.add(LzFolder.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    final path = <PathNode>[];
    final info = map['info'];
    if (info is List) {
      for (final item in info) {
        if (item is Map && item['folderid'] != null && item['name'] != null) {
          path.add(
            PathNode(id: '${item['folderid']}', name: '${item['name']}'),
          );
        }
      }
    }
    return (folders: folders, path: path);
  }

  /// 新建文件夹，返回新文件夹 id（同名文件夹已存在时直接复用其 id）。
  Future<String> mkdir(String parentId, String name, {String desc = ''}) async {
    final safe = name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'''[\$%^!*<>)(+=`'"/:;,?]'''), '');
    final existing = await listFolders(parentId);
    for (final folder in existing.folders) {
      if (folder.name == safe) return folder.id;
    }
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
      throw const LanzouException(
        '新建文件夹失败',
        code: LanzouErrorCode.createFolderFailed,
      );
    }
    final beforeIds = existing.folders.map((f) => f.id).toSet();
    final after = await listFolders(parentId);
    final added = after.folders
        .where((f) => !beforeIds.contains(f.id))
        .toList();
    if (added.isEmpty) {
      throw const LanzouException(
        '新建文件夹失败',
        code: LanzouErrorCode.createFolderFailed,
      );
    }
    return added.first.id;
  }

  Future<void> deleteItem({required String id, required bool isFile}) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: isFile ? {'task': 6, 'file_id': id} : {'task': 3, 'folder_id': id},
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException('删除失败', code: LanzouErrorCode.deleteFailed);
    }
  }

  /// 移动文件到目标文件夹（task 20）。
  Future<void> moveFile(String fileId, String folderId) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 20, 'file_id': fileId, 'folder_id': folderId},
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException(
        '移动文件失败',
        code: LanzouErrorCode.moveFileFailed,
      );
    }
  }

  /// 移动文件夹到目标父目录。
  /// 官方没有直接的文件夹移动接口，参照 LanZouCloud-API：
  /// 在目标目录重建同名文件夹，迁移其中的文件后删除原文件夹。
  /// 仅支持不含子文件夹的目录。
  Future<void> moveFolder(String folderId, String parentId) async {
    if (folderId == parentId) {
      throw const LanzouException(
        '不能移动到当前目录',
        code: LanzouErrorCode.moveToCurrentFolder,
      );
    }
    final subs = await listFolders(folderId);
    if (subs.folders.isNotEmpty) {
      throw const LanzouException(
        '暂不支持移动含子文件夹的目录',
        code: LanzouErrorCode.moveFolderWithSubfoldersUnsupported,
      );
    }
    final info = await shareInfoOfFolder(folderId);
    if (info.name.isEmpty) {
      throw const LanzouException(
        '无法读取文件夹信息',
        code: LanzouErrorCode.readFolderInfoFailed,
      );
    }
    final newId = await mkdir(parentId, info.name, desc: info.desc);
    if (newId == folderId) {
      throw const LanzouException(
        '目标位置与当前位置相同',
        code: LanzouErrorCode.sameTargetFolder,
      );
    }
    if (info.pwd.isNotEmpty) {
      await setFolderPasswd(newId, info.pwd);
    }
    for (final file in await listFiles(folderId)) {
      await moveFile(file.id, newId);
    }
    await deleteItem(id: folderId, isFile: false);
  }

  /// 修改文件简介（task 11）。
  /// 网页版文件夹信息页：直接读取该文件夹的统计信息。
  /// 解析失败返回 null，由调用方回退到遍历统计。
  Future<({String size, int count, String name, String desc, String url})?>
  folderStats(String folderId) async {
    try {
      final resp = await dio.get<String>(
        '$apiBase/myfile.php?item=3&folder_id=$folderId&v2',
        options: _options(referer: '$apiBase/mydisk.php'),
      );
      final html = resp.data ?? '';
      if (html.isEmpty || html.contains('网盘用户登录')) {
        return null;
      }
      final size =
          RegExp(r'<div class="folsha2">大小<div class="folsha3">([^<]*)</div>')
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '';
      final count =
          int.tryParse(
            RegExp(r'<div class="folsha2">文件数<div class="folsha3">(\d+)</div>')
                    .firstMatch(html)
                    ?.group(1) ??
                '',
          ) ??
          0;
      final name =
          RegExp(r'id="foldertxt"[^>]*value="([^"]*)"')
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '';
      final desc =
          RegExp(r'id="folderinfo"[^>]*value="([^"]*)"')
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '';
      final url =
          RegExp(r'class="f_pwdurl"[^>]*>(https?://[^<]+)</div>')
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
      throw const LanzouException(
        '修改简介失败',
        code: LanzouErrorCode.updateDescriptionFailed,
      );
    }
  }

  /// 修改文件名（task 46）。
  ///
  /// 蓝奏云的重命名接口只对会员开放：免费账号服务端会返回失败，这里
  /// 把失败原因写清楚，免得用户以为是网络问题。
  Future<void> setFileName(String fileId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const LanzouException(
        '文件名不能为空',
        code: LanzouErrorCode.fileNameRequired,
      );
    }
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {
        'task': 46,
        'file_id': int.tryParse(fileId) ?? fileId,
        'file_name': trimmed,
        'type': 2,
      },
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException(
        '重命名失败：此功能需要开通会员',
        code: LanzouErrorCode.renameRequiresMembership,
      );
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
      throw const LanzouException(
        '设置访问密码失败',
        code: LanzouErrorCode.updateFilePasswordFailed,
      );
    }
  }

  /// 修改文件夹简介：先 task 18 取当前名称，再 task 4 保存。
  Future<void> setFolderDesc(String folderId, String desc) async {
    final current = await _folderInfoForUpdate(folderId);
    await setFolderInfo(folderId, name: current.name, desc: desc);
  }

  /// 修改文件夹名称：先 task 18 取当前简介，再 task 4 原样保存。
  ///
  /// task 4 会同时提交名称和简介，不能只传新名称，否则会覆盖已有简介。
  Future<void> renameFolder(String folderId, String name) async {
    final current = await _folderInfoForUpdate(folderId);
    await setFolderInfo(folderId, name: name, desc: current.desc);
  }

  Future<({String name, String desc})> _folderInfoForUpdate(
    String folderId,
  ) async {
    final infoResp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 18, 'folder_id': folderId},
      options: _options(),
    );
    final info = _requireMap(
      _asMap(infoResp.data)['info'],
      message: '无法读取文件夹信息',
      code: LanzouErrorCode.readFolderInfoFailed,
    );
    final name = '${info['name'] ?? ''}';
    final desc = '${info['des'] ?? ''}';
    return (name: name, desc: desc);
  }

  /// 修改文件夹信息（名称 + 简介）：task 4。
  Future<void> setFolderInfo(
    String folderId, {
    required String name,
    required String desc,
  }) async {
    if (name.trim().isEmpty) {
      throw const LanzouException(
        '文件夹名称不能为空',
        code: LanzouErrorCode.folderNameRequired,
      );
    }
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {
        'task': 4,
        'folder_id': folderId,
        'folder_name': name.trim(),
        'folder_description': desc,
      },
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException(
        '保存文件夹信息失败',
        code: LanzouErrorCode.updateFolderInfoFailed,
      );
    }
  }

  /// 设置文件夹访问密码（task 16，免费账号只能设置不能关闭）。
  Future<void> setFolderPasswd(String folderId, String pwd) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {
        'task': 16,
        'folder_id': folderId,
        'shows': pwd.isEmpty ? 0 : 1,
        'shownames': pwd,
      },
      options: _options(),
    );
    if ('${_asMap(resp.data)['zt']}' != '1') {
      throw const LanzouException(
        '设置文件夹访问密码失败',
        code: LanzouErrorCode.updateFolderPasswordFailed,
      );
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
      throw const LanzouException(
        '没有可上传的文件内容',
        code: LanzouErrorCode.uploadContentMissing,
      );
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
      uploadUrl,
      data: form,
      cancelToken: cancelToken,
      onSendProgress: (sent, total) => onProgress?.call(sent, total),
      options: Options(
        headers: {'Referer': '$apiBase/mydisk.php'},
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(hours: 2),
        receiveTimeout: const Duration(minutes: 10),
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final map = _asMap(resp.data);
    if ('${map['zt']}' != '1') {
      throw LanzouException(
        '上传失败：${map['info'] ?? '未知错误'}',
        code: LanzouErrorCode.uploadFailed,
        detail: '${map['info'] ?? ''}',
      );
    }
  }

  // ------------------------------------------------------------------ share

  /// 新版个人中心里的昵称：`utcn()` 中 `/u/<用户名>` 的最后一段。
  static String? parseProfileNickname(String html) {
    final match = RegExp(
      r'''function\s+utcn\s*\(\s*\)\s*\{[\s\S]*?url\s*=\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    ).firstMatch(html);
    final rawUrl = match?.group(1)?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri != null) {
      final segments = uri.pathSegments;
      for (var i = 0; i + 1 < segments.length; i++) {
        if (segments[i] == 'u' && segments[i + 1].isNotEmpty) {
          return Uri.decodeComponent(segments[i + 1]);
        }
      }
    }
    final pathName = RegExp(r'/u/([^/?#]+)').firstMatch(rawUrl)?.group(1);
    if (pathName == null || pathName.isEmpty) return null;
    try {
      return Uri.decodeComponent(pathName);
    } catch (_) {
      return pathName;
    }
  }

  /// 从新版个人中心 HTML 里解析昵称与等级。
  ///
  /// 新页优先；保留旧页顶栏 / `shownames` 规则，既用于旧链接回退，也让
  /// 页面改版但仍有旧标记时不丢昵称。
  static ({String? nickname, String level}) parseAccountInfoHtml(String html) {
    final profileName = parseProfileNickname(html);
    final loginName = RegExp(r'<div class="c_topr">\s*([^<]+?)\s*<span')
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    final fallback = RegExp(r'id="shownames"[^>]*value="([^"]*)"')
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    final name =
        profileName ??
        (loginName != null && loginName.isNotEmpty ? loginName : fallback);
    // 等级：昵称旁边那个等级标记（普通用户是 <span class="ulv1">普</span>）。
    // 从顶栏那块往后找，避免误取页面别处的等级图标。
    final topRight = html.indexOf('c_topr');
    final scope = topRight < 0 ? html : html.substring(topRight);
    final level =
        RegExp(r'<span[^>]*class="ulv[^"]*"[^>]*>\s*([^<]*?)\s*</span>')
            .firstMatch(scope)
            ?.group(1)
            ?.trim() ??
        '';
    return (nickname: name == null || name.isEmpty ? null : name, level: level);
  }

  /// 解析新版个人中心里的单文件上限；找不到或格式异常时回退到 100 MB。
  static int parseUploadLimitBytes(String html) {
    final raw = RegExp(r'单个文件大小\s*<span[^>]*>\s*([^<]+?)\s*</span>')
        .firstMatch(html)
        ?.group(1)
        ?.trim()
        .toUpperCase()
        .replaceAll(' ', '');
    if (raw == null || raw.isEmpty) return kFallbackUploadLimitBytes;
    final match = RegExp(r'^(\d+(?:\.\d+)?)([KMGT]?)(?:I?B)?$').firstMatch(raw);
    if (match == null) return kFallbackUploadLimitBytes;
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null || number <= 0) return kFallbackUploadLimitBytes;
    final unit = match.group(2) ?? '';
    final multiplier = switch (unit) {
      'K' => 1024,
      'M' => 1024 * 1024,
      'G' => 1024 * 1024 * 1024,
      'T' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    final bytes = (number * multiplier).round();
    return bytes > 0 ? bytes : kFallbackUploadLimitBytes;
  }

  /// 解析新版个人中心里的允许上传扩展名；找不到时回退到内置完整列表。
  static Set<String> parseAllowedUploadExtensions(String html) {
    final block =
        RegExp(
          r'允许上传类型\s*[:：]?\s*</div>\s*<div[^>]*class="mf2"[^>]*>([\s\S]*?)</div>',
          caseSensitive: false,
        ).firstMatch(html)?.group(1) ??
        '';
    if (block.isEmpty) return kFallbackUploadExtensions;
    final text = block
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ',')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&nbsp', ' ');
    final extensions = <String>{};
    for (final part in text.split(RegExp(r'[,，\s]+'))) {
      final extension = part.trim().replaceFirst(RegExp(r'^\.+'), '');
      if (extension.isNotEmpty) extensions.add(extension.toLowerCase());
    }
    return extensions.isEmpty ? kFallbackUploadExtensions : extensions;
  }

  /// 从同一份新版个人中心 HTML 中提取完整上传约束。
  static LanzouUploadPolicy parseUploadPolicyHtml(String html) =>
      LanzouUploadPolicy(
        maxFileBytes: parseUploadLimitBytes(html),
        allowedExtensions: parseAllowedUploadExtensions(html),
      );

  /// 网页版个人中心信息：昵称、等级、单文件上限与上传白名单。
  ///
  /// 新版页只请求一次。昵称解析失败时才回退旧版页补昵称 / 等级；大小和
  /// 白名单不会从旧页重试。最终仍取不到昵称时使用「用户」占位。
  Future<({String? nickname, String level, LanzouUploadPolicy uploadPolicy})>
  fetchAccountInfo({bool refresh = false}) {
    if (!refresh &&
        _accountInfoRequest != null &&
        _accountInfoRequestBase == apiBase) {
      return _accountInfoRequest!;
    }
    _accountInfoRequestBase = apiBase;
    final request = _loadAccountInfo();
    _accountInfoRequest = request;
    return request;
  }

  Future<({String? nickname, String level, LanzouUploadPolicy uploadPolicy})>
  _loadAccountInfo() async {
    String? nickname;
    var level = '';
    var uploadPolicy = LanzouUploadPolicy.fallback;
    try {
      final resp = await dio.get<String>(
        accountProfileUrl,
        options: _options(referer: '$apiBase/mydisk.php'),
      );
      final html = resp.data ?? '';
      if (html.isNotEmpty && !html.contains('网盘用户登录')) {
        final parsed = parseAccountInfoHtml(html);
        nickname = parsed.nickname;
        level = parsed.level;
        uploadPolicy = parseUploadPolicyHtml(html);
      }
    } catch (_) {}

    if (nickname == null) {
      try {
        final legacy = await dio.get<String>(
          '$apiBase/myfile.php?item=1&v2',
          options: _options(referer: '$apiBase/mydisk.php'),
        );
        final html = legacy.data ?? '';
        if (html.isNotEmpty && !html.contains('网盘用户登录')) {
          final parsed = parseAccountInfoHtml(html);
          nickname = parsed.nickname;
          if (level.isEmpty) level = parsed.level;
        }
      } catch (_) {}
    }

    _uploadPolicy = uploadPolicy;
    return (
      nickname: nickname ?? kFallbackAccountNickname,
      level: level,
      uploadPolicy: uploadPolicy,
    );
  }

  Future<ShareInfo> shareInfoOfFile(
    String fileId, {
    bool withDetails = true,
  }) async {
    final resp = await dio.post<String>(
      '$apiBase/doupload.php',
      data: {'task': 22, 'file_id': fileId},
      options: _options(),
    );
    final info = _requireMap(
      _asMap(resp.data)['info'],
      message: '无法获取该文件的分享信息',
      code: LanzouErrorCode.fileShareInfoFailed,
    );
    final fId = '${info['f_id'] ?? ''}';
    if (fId.isEmpty || fId == 'i') {
      throw const LanzouException(
        '无法获取该文件的分享信息',
        code: LanzouErrorCode.fileShareInfoFailed,
      );
    }
    var name = '${info['name'] ?? ''}';
    var desc = '';
    if (withDetails) {
      try {
        final extra = _asMap(
          (await dio.post<String>(
            '$apiBase/doupload.php',
            data: {'task': 12, 'file_id': fileId},
            options: _options(),
          )).data,
        );
        name = '${extra['text'] ?? name}';
        desc = '${extra['info'] ?? ''}';
      } catch (_) {}
    }
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
      queryParameters: {'uid': uid},
      data: {'task': 18, 'folder_id': folderId, 'pg': ''},
      options: _options(),
    );
    final map = _asMap(resp.data);
    if ('${map['zt']}' != '1') {
      throw LanzouException(
        '${map['info'] ?? '获取文件夹分享信息失败'}',
        code: LanzouErrorCode.folderShareInfoFailed,
        detail: '${map['info'] ?? ''}',
      );
    }
    final info = _requireMap(
      map['info'],
      message: '无法获取该文件夹的分享信息',
      code: LanzouErrorCode.folderShareInfoFailed,
    );
    return ShareInfo(
      url: '${info['new_url'] ?? ''}',
      pwd: '${info['onof']}' == '1' ? '${info['pwd']}' : '',
      isFile: false,
      name: '${info['name'] ?? ''}',
      desc: '${info['des'] ?? ''}',
    );
  }

  Future<String> fetchSharePage(String url, {String? referer}) async {
    var resp = await dio.get<String>(
      url,
      options: _options(referer: referer ?? url),
    );
    var html = resp.data ?? '';
    if (html.contains('acw_sc__v2')) {
      final token = calcAcwScV2(html);
      if (token.isNotEmpty) {
        _jar.putIfAbsent(Uri.parse(url).host, () => {})['acw_sc__v2'] = token;
        resp = await dio.get<String>(
          url,
          options: _options(referer: referer ?? url),
        );
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
    final def = RegExp('var\\s+${RegExp.escape(t)}\\s*=\\s*([^;]+);')
        .firstMatch(html);
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
    final endpointRaw =
        _match(pageHtml, [
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
        RegExp(
          r'data\s*:\s*\{([^}]*)\}',
          dotAll: true,
        ).firstMatch(pageHtml)?.group(1) ??
        '';
    final fields = <String, String>{};
    for (final m in RegExp(
      r"""['"]?(\w+)['"]?\s*:\s*([^,}]+)""",
    ).allMatches(block)) {
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

  /// 只解析分享页上可直接展示的元信息，不生成会过期的下载直链。
  Future<ShareFileDetails> fetchFileShareDetails(
    String shareUrl, {
    String pwd = '',
    bool withDescription = false,
  }) async {
    Object? lastError;
    for (final candidate in _shareUrlCandidates(shareUrl)) {
      try {
        final page = await _loadFileSharePageOn(
          candidate,
          pwd,
          withDescription: withDescription,
          requirePassword: false,
        );
        return ShareFileDetails(
          name: page.nameResolved ? page.name : '',
          size: page.size,
          time: page.time,
          desc: page.desc,
          sharer: page.sharer,
          requiresPassword: page.needPwd,
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError is LanzouException
        ? lastError
        : LanzouException(
            '解析分享详情失败：$lastError',
            code: LanzouErrorCode.resolveShareFailed,
            detail: '$lastError',
          );
  }

  Future<DirectFile> resolveFileShare(
    String shareUrl, {
    String pwd = '',

    /// 是否连下载页（/tp）一起取简介：属性弹窗打开，批量解析 / 下载不需要。
    bool withDescription = false,
  }) async {
    Object? lastError;
    for (final candidate in _shareUrlCandidates(shareUrl)) {
      try {
        return await _resolveFileShareOn(
          candidate,
          pwd,
          withDescription: withDescription,
        );
      } on NeedPasswordException {
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError is LanzouException
        ? lastError
        : LanzouException(
            '解析分享失败：$lastError',
            code: LanzouErrorCode.resolveShareFailed,
            detail: '$lastError',
          );
  }

  Future<DirectFile> _resolveFileShareOn(
    String url,
    String pwd, {
    bool withDescription = false,
  }) async {
    final page = await _loadFileSharePageOn(
      url,
      pwd,
      withDescription: withDescription,
      requirePassword: true,
    );
    final uri = page.uri;
    final base = page.base;
    final html = page.html;
    final needPwd = page.needPwd;
    final name = page.name;
    final size = page.size;
    final desc = page.desc;
    final sharer = page.sharer;
    final legacyHtml = page.legacyHtml;
    final iframeUrl = page.iframeUrl;
    final iframeHtml = page.iframeHtml;

    if (iframeHtml != null && iframeUrl != null) {
      final direct = await _resolveViaAjaxFile(iframeHtml, iframeUrl, url, pwd);
      if (direct != null) {
        return DirectFile(
          name: name,
          url: direct,
          size: size,
          desc: desc,
          sharer: sharer,
        );
      }
    }

    // 新版密码流程：首页 JS 自带 isngis(sign)/kdns(kd)，直接 POST ajaxfile.php
    if (needPwd) {
      final passwordDirect = await _resolvePasswordShare(
        html,
        url,
        uri,
        base,
        pwd,
      );
      if (passwordDirect != null) {
        return DirectFile(
          name: passwordDirect.name.isEmpty ? name : passwordDirect.name,
          url: passwordDirect.url,
          size: size,
          desc: desc,
          sharer: sharer,
        );
      }
    }

    // 旧版流程回退：ajaxm.php
    String? sign;
    if (needPwd) {
      final pwdSign = RegExp(r'sign=(\w+?)&').firstMatch(html)?.group(1);
      if (pwdSign == null) {
        throw const LanzouException(
          '提取码参数解析失败',
          code: LanzouErrorCode.passwordParameterParseFailed,
        );
      }
      sign = pwdSign;
    } else {
      var rawSign =
          RegExp(r"'sign':(.+?),").firstMatch(legacyHtml)?.group(1) ?? '';
      rawSign = rawSign.replaceAll("'", '').trim();
      if (rawSign.isNotEmpty && rawSign.length < 20) {
        final resolved = _resolveJsValue(legacyHtml, rawSign);
        if (resolved.isNotEmpty) rawSign = resolved;
      }
      sign = rawSign;
    }
    if (sign.isEmpty) {
      throw const LanzouException(
        '下载参数解析失败',
        code: LanzouErrorCode.downloadParameterParseFailed,
      );
    }
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
      final info = '${link['inf'] ?? link['info'] ?? ''}';
      if (info.contains('密码') || info.contains('提取码')) {
        throw const WrongPasswordException();
      }
      throw LanzouException(
        '获取下载地址失败：${info.isEmpty ? link : info}',
        code: LanzouErrorCode.downloadUrlFailed,
        detail: '${info.isEmpty ? link : info}',
      );
    }
    final dom = '${link['dom'] ?? ''}';
    final path = '${link['url'] ?? ''}';
    final direct = path.startsWith('http')
        ? path
        : await _followDownloadRedirect(dom, path, url);
    if (direct == null || direct.isEmpty) {
      throw const LanzouException(
        '未获取到直链',
        code: LanzouErrorCode.directLinkMissing,
      );
    }
    return DirectFile(
      name: name,
      url: direct,
      size: size,
      desc: desc,
      sharer: sharer,
    );
  }

  /// 加载分享页并解析属性弹窗所需的元信息。
  ///
  /// [requirePassword] 为 false 时，需要提取码的分享也能在未提供密码时返回
  /// 基本元信息；真正生成直链时仍会由 [resolveFileShare] 强制校验密码。
  Future<_FileSharePageContext> _loadFileSharePageOn(
    String url,
    String pwd, {
    required bool withDescription,
    required bool requirePassword,
  }) async {
    final uri = Uri.parse(url);
    final base = '${uri.scheme}://${uri.host}';
    final html = await fetchSharePage(url);
    if (html.contains('文件不存') || html.contains('文件取消')) {
      throw const LanzouException(
        '文件不存在或已取消分享',
        code: LanzouErrorCode.fileShareUnavailable,
      );
    }
    final needPwd =
        html.contains('id="pwdload"') || html.contains('id="passwddiv"');
    if (requirePassword && needPwd && pwd.isEmpty) {
      throw const NeedPasswordException();
    }

    final parsedName = _match(html, [
      r'<title>(.+?) - 蓝奏云</title>',
      r'<div class="filethetext".+?>([^<>]+?)</div>',
    ]);
    var nameResolved = parsedName != null;
    var name = parsedName ?? url.split('/').last;
    final size = shareFileSizeFromHtml(html);
    var time = shareFileTimeFromHtml(html);
    final sharer =
        _match(html, [
          r'<span class="user-name">([^<]+)</span>',
          r'class="user-name"[^>]*>([^<]+)<',
        ]) ??
        '';
    var desc = _cleanDesc(
      _match(html, [r'class="n_box_des">(.*?)</div>']) ?? '',
    );
    // app 用桌面 UA 请求时会返回 PC 版模板：简介写在「文件描述：」表格里
    // （exe / 普通文件的分享页就是这种），APK 模板没有这个字段。
    if (desc.isEmpty) {
      desc = pcShareDescriptionFromHtml(html) ?? desc;
    }

    // 新版流程：分享页 -> iframe -> ajaxfile.php。仅解析属性时如果分享页
    // 已明确需要提取码且当前没有密码，不额外进入 iframe。
    final iframeRaw = RegExp(r'<iframe.*?src="(.+?)"')
        .firstMatch(html)
        ?.group(1);
    var legacyHtml = html;
    String? iframeUrl;
    String? iframeHtml;
    if (iframeRaw != null && (!needPwd || pwd.isNotEmpty)) {
      iframeUrl = _absoluteUrl(base, uri.scheme, iframeRaw);
      iframeHtml = await fetchSharePage(iframeUrl);
      legacyHtml = iframeHtml;
      final frameTitle = _match(iframeHtml, [r'<title>(.+?)</title>']);
      if (frameTitle != null && frameTitle.trim().isNotEmpty) {
        name = frameTitle.trim();
        nameResolved = true;
      }
      final frameDesc = _match(iframeHtml, [r'class="n_box_des">(.*?)</div>']);
      if (frameDesc != null) {
        final cleaned = _cleanDesc(frameDesc);
        // iframe 里是空的就别覆盖分享页已解析到的简介
        if (cleaned.isNotEmpty) desc = cleaned;
      }
      final frameTime = shareFileTimeFromHtml(iframeHtml);
      if (frameTime.isNotEmpty) time = frameTime;
    }

    // exe / apk 等分享页模板没有简介节点：下载页（/tp）的 .mdo 才是简介。
    // 只在属性弹窗（需要简介）且分享页没解析到简介时多请求一次。
    if (withDescription && desc.isEmpty) {
      final tpDesc = await _fetchTpDescription(html, base, uri.scheme, url);
      if (tpDesc != null && tpDesc.isNotEmpty) desc = tpDesc;
    }

    return _FileSharePageContext(
      uri: uri,
      base: base,
      html: html,
      needPwd: needPwd,
      name: name,
      nameResolved: nameResolved,
      size: size,
      time: time,
      desc: desc,
      sharer: sharer,
      legacyHtml: legacyHtml,
      iframeUrl: iframeUrl,
      iframeHtml: iframeHtml,
    );
  }

  String _cleanDesc(String raw) {
    return _cleanShareText(raw);
  }

  /// 从下载页（/tp）抓简介：exe / apk 等模板把简介放在 `.mdo` 里。
  Future<String?> _fetchTpDescription(
    String pageHtml,
    String base,
    String scheme,
    String pageUrl,
  ) async {
    final raw = RegExp(r"link\.href\s*=\s*'([^']+)'")
        .firstMatch(pageHtml)
        ?.group(1);
    if (raw == null || raw.isEmpty) return null;
    final tpUrl = _absoluteUrl(base, scheme, raw);
    try {
      final html = await fetchSharePage(tpUrl, referer: pageUrl);
      return tpDescriptionFromHtml(html);
    } catch (_) {
      return null;
    }
  }

  /// 新版带密码分享：首页直接 POST ajaxfile.php（isngis 作 sign、kdns 作 kd、p 为提取码）。
  Future<DirectFile?> _resolvePasswordShare(
    String html,
    String url,
    Uri uri,
    String base,
    String pwd,
  ) async {
    final signCandidates = RegExp(r"var\s+isngis\s*=\s*'([^']*)'")
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((s) => s.isNotEmpty)
        .toList();
    final endpointRaw = RegExp(r"url\s*:\s*'([^']*ajaxfile\.php[^']*)'")
        .firstMatch(html)
        ?.group(1);
    if (signCandidates.isEmpty || endpointRaw == null) return null;
    final kd =
        RegExp(r'var\s+kdns\s*=\s*([^;]+);')
            .firstMatch(html)
            ?.group(1)
            ?.trim() ??
        '1';
    final lanosso =
        RegExp(r"var\s+lanosso\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ??
        '';
    final endpoint = _absoluteUrl(base, uri.scheme, endpointRaw);
    final resp = await dio.post<String>(
      endpoint,
      data: <String, dynamic>{
        'action': 'downprocess',
        'sign': signCandidates.last,
        'kd': kd,
        'p': pwd,
      },
      options: _options(referer: url),
    );
    final map = _asMap(resp.data);
    if ('${map['zt']}' != '1') {
      final info = '${map['inf'] ?? map['info'] ?? ''}';
      // 提取码错误单独成类：弹窗会像「该分享需要提取码」一样标在输入框上
      if ('${map['zt']}' == '3' ||
          info.contains('密码') ||
          info.contains('提取码')) {
        throw const WrongPasswordException();
      }
      throw LanzouException(info.isNotEmpty ? info : '提取码错误或获取下载地址失败');
    }
    final dom = '${map['dom'] ?? ''}';
    final pathRaw = '${map['url'] ?? ''}';
    final path = lanosso.isNotEmpty && !pathRaw.contains(lanosso)
        ? '$pathRaw$lanosso'
        : pathRaw;
    final name = '${map['inf'] ?? ''}'.replaceAll('*', '_');
    if (path.startsWith('http')) return DirectFile(name: name, url: path);
    if (path.startsWith('?') && dom.isNotEmpty) {
      final directUrl = '$dom/file/$path';
      await _primeDirectUrl(directUrl);
      return DirectFile(name: name, url: directUrl);
    }
    if (dom.isNotEmpty && path.isNotEmpty) {
      final direct = await _followDownloadRedirect(dom, path, url);
      if (direct != null && direct.isNotEmpty) {
        return DirectFile(name: name, url: direct);
      }
      return DirectFile(name: name, url: '$dom/file/$path');
    }
    return null;
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
      throw const LanzouException(
        '文件夹不存在或已取消分享',
        code: LanzouErrorCode.folderShareUnavailable,
      );
    }
    final needPwd =
        html.contains('id="pwdload"') || html.contains('id="passwddiv"');
    if (needPwd && pwd.isEmpty) throw const NeedPasswordException();
    final lx = _match(html, [r"'lx':'?(\d)'?,"]);
    final t = _match(html, [r"var [0-9a-z_]{6} = '(\d{10})';"]);
    final k = _match(html, [r"var [0-9a-z_]{6} = '([0-9a-z]{15,})';"]);
    final fid = _match(html, [
      r"'fid':'?(\d+)'?,",
      r'filemoreajax\.php\?file=(\d+)',
    ]);
    final uid = _match(html, [r"'uid'\s*:\s*'(\d+)'"]);
    final puid = _match(html, [r"'puid'\s*:\s*'([^']+)'"]);
    if (lx == null || t == null || k == null || fid == null) {
      throw const LanzouException(
        '分享页结构解析失败',
        code: LanzouErrorCode.sharePageParseFailed,
      );
    }
    final name =
        _match(html, [
          r'<title>([^<]*)</title>',
          r"var.+?='(.+?)';\n.+document.title",
          r'<div class="user-title">(.+?)</div>',
        ]) ??
        '';
    final desc =
        _match(html, [
          r'id="filename">(.+?)</span>',
          r'<div class="user-radio-\d"></div>(.+?)</div>',
        ]) ??
        '';
    final sharer =
        _match(html, [
          r'<span class="user-name">([^<]+)</span>',
          r'class="user-name"[^>]*>([^<]+)<',
        ]) ??
        '';
    final paging = ShareFolderPaging(
      base: base,
      referer: url,
      fid: fid,
      lx: lx,
      t: t,
      k: k,
      uid: uid,
      puid: puid,
      pwd: pwd,
    );
    // 只取第一页：文件夹里文件很多时不再等全部加载完才进浏览页，
    // 后续分页由浏览页按「自动加载全部目录内容」设置与滚动位置继续拉取。
    final first = await fetchShareFolderFiles(paging, 1);
    final folders = <SubFolder>[];
    for (final m in RegExp(
      r'mbxfolder"><a href="(.+?)".+class="filename">(.+?)<div class="filesize">(.*?)</div>',
      dotAll: true,
    ).allMatches(html)) {
      final href = m.group(1)!;
      folders.add(
        SubFolder(
          name: m.group(2)!,
          desc: m.group(3)!,
          url: href.startsWith('http') ? href : '$base$href',
        ),
      );
    }
    return FolderShareDetail(
      name: name,
      desc: desc,
      sharer: sharer,
      files: first.files,
      folders: folders,
      paging: paging,
      hasMore: first.hasMore,
    );
  }

  /// 拉取分享文件夹的某一页文件（与网盘页一致：滑到底再加载下一页）。
  /// 返回该页文件与是否可能还有下一页；zt=2 表示已到底。
  ///
  /// 服务端在「请求来得太频繁 / 一时拿不到数据」时可能回 zt=4、未知状态，
  /// 或者干脆给个解析不出来的响应。这些都是「稍后再试」，不是真的失败：
  /// 这里退避重试几次，避免偶发失败冒到界面上（真机上表现为底部闪「重试」）。
  Future<({List<ShareFileItem> files, bool hasMore})> fetchShareFolderFiles(
    ShareFolderPaging paging,
    int page,
  ) async {
    const maxAttempts = 4;
    // 服务端忙时会回「请刷新，重试N」，要求把 N 填回 rep 再请求一次；
    // 其它「稍后再试」的情况（zt=4 / 未知状态）就自己把 rep 加一。
    var rep = 0;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final lastAttempt = attempt == maxAttempts;
      final Map<String, dynamic> map;
      try {
        final resp = await dio.post<String>(
          '${paging.base}/filemoreajax.php?file=${paging.fid}',
          data: <String, dynamic>{
            'lx': paging.lx,
            'fid': paging.fid,
            'uid': ?paging.uid,
            'puid': ?paging.puid,
            'pg': page,
            'rep': '$rep',
            't': paging.t,
            'k': paging.k,
            'up': 1,
            if (paging.pwd.isNotEmpty) 'pwd': paging.pwd,
          },
          options: _options(referer: paging.referer),
        );
        map = _asMap(resp.data);
      } catch (e) {
        // 空响应 / 挑战页这类解析失败同样是「一时拿不到」
        if (lastAttempt) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        continue;
      }
      final zt = '${map['zt']}';
      if (zt == '1') {
        final files = <ShareFileItem>[];
        final text = map['text'];
        // 「本页不足一页（50 条）就没有下一页」这条规则要按服务端返回的
        // 原始条数判断：文件夹里可能有 id 为 -1 的屏蔽文件（例如 ***.apk），
        // 它们照样要展示，用过滤后的条数判断会把 49 条误判成最后一页。
        var returned = 0;
        if (text is List) {
          for (final item in text) {
            if (item is Map) {
              returned += 1;
              final id = '${item['id'] ?? ''}';
              // 屏蔽 / 失效条目：保留下来占位，但标为不可用（下载等操作禁用）
              final invalid = id.isEmpty || id == '-1';
              files.add(
                ShareFileItem(
                  name: '${item['name_all'] ?? ''}',
                  time: '${item['time'] ?? ''}',
                  size: '${item['size'] ?? ''}',
                  url: invalid
                      ? ''
                      : id.startsWith('http')
                      ? id
                      : '${paging.base}/$id',
                  invalid: invalid,
                ),
              );
            }
          }
        }
        // 分享页自己的 JS 就是按「本页不足一页（50 条）→ 没有更多」判断的
        // （data.length < 50 时把 filemore 藏起来），这里照抄同一条规则：
        // 文件不满 50 个的文件夹第一页就判定到底，不用再发一次「下一页」请求
        // （少一次请求，也就不会因为服务端偶发「请刷新」而闪重试）
        return (files: files, hasMore: returned >= _shareFilesPerPage);
      }
      if (zt == '2') return (files: const <ShareFileItem>[], hasMore: false);
      if (zt == '3') throw const WrongPasswordException();
      final info = '${map['info'] ?? ''}';
      // 「请刷新，重试N」是服务端的重试指令，不是真错误
      final hint = RegExp(r'重试\s*(\d+)').firstMatch(info);
      // 其它带信息的响应（文件不存在 / 提取码错误等）直接报错，不做无谓重试
      if (info.isNotEmpty && hint == null) throw LanzouException(info);
      rep = hint == null ? rep + 1 : (int.tryParse(hint.group(1)!) ?? rep + 1);
      // zt=4 / 未知状态 / 「请刷新」：稍等后按新的 rep 重试同一页
      if (lastAttempt) break;
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
    throw const LanzouException(
      '获取分享文件列表失败',
      code: LanzouErrorCode.shareFileListFailed,
    );
  }
}

class _FileSharePageContext {
  const _FileSharePageContext({
    required this.uri,
    required this.base,
    required this.html,
    required this.needPwd,
    required this.name,
    required this.nameResolved,
    required this.size,
    required this.time,
    required this.desc,
    required this.sharer,
    required this.legacyHtml,
    required this.iframeUrl,
    required this.iframeHtml,
  });

  final Uri uri;
  final String base;
  final String html;
  final bool needPwd;
  final String name;
  final bool nameResolved;
  final String size;
  final String time;
  final String desc;
  final String sharer;
  final String legacyHtml;
  final String? iframeUrl;
  final String? iframeHtml;
}

/// 从分享文件页 HTML 解析大小（返回如 `1.1M`，解析不到返回空串）。
///
/// 文件页把大小写在 meta description（`大小：1.1 M`）和下载按钮里
/// （`下载 ( 1.1 M )`）。旧写法 `大小.+?(\d...)<` 带 dotAll，会一路跨行
/// 吃到页面里的日期 `2026-06-22<`，于是所有文件都被读成 `22`（22.0 MB）；
/// 这里只认「大小：数字+单位」这种紧邻的写法，不再用跨行通配。
String shareFileSizeFromHtml(String html) {
  final match =
      RegExp(
        r'content="大小[：:]\s*([\d.,]+\s*[BKMGT]?)"',
        caseSensitive: false,
      ).firstMatch(html) ??
      RegExp(r'下载\s*\(\s*([\d.,]+\s*[BKMGT]?)\s*\)').firstMatch(html) ??
      RegExp(
        r'大小[：:]\s*([\d.,]+\s*[BKMGT]?)',
        caseSensitive: false,
      ).firstMatch(html);
  final raw = match?.group(1) ?? '';
  return raw.replaceAll(',', '').replaceAll(RegExp(r'\s+'), '');
}

/// 从分享文件页解析文件时间。
///
/// APK 模板用 `appinfotime` 节点；部分 PC 模板会把时间写在明确的时间标签后。
/// 这里只接受已知节点/标签，不抓页面里的任意日期，避免把统计或其他日期误当文件时间。
String shareFileTimeFromHtml(String html) {
  final match =
      RegExp(
        r'class="appinfotime"[^>]*>\s*([^<]+?)\s*<',
        caseSensitive: false,
      ).firstMatch(html) ??
      RegExp(
        r'(?:上传时间|文件时间|分享时间)[：:]\s*(?:</span>\s*)?([^<]+?)\s*<',
        caseSensitive: false,
      ).firstMatch(html);
  return match?.group(1)?.trim() ?? '';
}

/// 清理分享页里的富文本（简介、描述）：保留换行、去掉标签与常见实体。
String _cleanShareText(String raw) {
  return raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
}

/// 从下载页（/tp）HTML 取真正的简介。
///
/// 有简介的文件，`.mdo` 是上传者写的内容；没写简介时这里是系统默认的
/// 「下载说明」（建议网络 / 反馈），不能当成简介显示。
String? tpDescriptionFromHtml(String html) {
  final raw = RegExp(
    r'<div class="mdo">(.*?)</div>',
    dotAll: true,
  ).firstMatch(html)?.group(1);
  if (raw == null) return null;
  final text = _cleanShareText(raw);
  if (text.isEmpty) return null;
  if (text.contains('下载说明') || text.contains('建议使用最快的网络')) {
    return null;
  }
  return text;
}

/// 从 PC 版分享页取「文件描述」。
///
/// app 用桌面 UA 请求，exe / 普通文件页返回的是 PC 模板：
/// `<span class="p7">文件描述：</span><br>简介</td>`；
/// APK 等没有这个字段时返回 null。
String? pcShareDescriptionFromHtml(String html) {
  final raw = RegExp(
    r'<span class="p7">文件描述[：:]\s*</span>\s*<br\s*/?>\s*(.*?)</td>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(html)?.group(1);
  if (raw == null) return null;
  final text = _cleanShareText(raw);
  return text.isEmpty ? null : text;
}
