/// 蓝奏云网页未取到限制时使用的单文件大小上限。
const int kFallbackUploadLimitBytes = 100 * 1024 * 1024;

/// 蓝奏云网页未取到白名单时使用的允许上传扩展名。
const Set<String> kFallbackUploadExtensions = {
  'doc',
  'docx',
  'zip',
  'rar',
  'apk',
  'txt',
  'exe',
  '7z',
  'e',
  'z',
  'ct',
  'ke',
  'cetrainer',
  'db',
  'tar',
  'pdf',
  'w3x',
  'epub',
  'mobi',
  'azw',
  'azw3',
  'osk',
  'osz',
  'xpa',
  'cpk',
  'lua',
  'jar',
  'dmg',
  'ppt',
  'pptx',
  'xls',
  'xlsx',
  'mp3',
  'ipa',
  'iso',
  'img',
  'gho',
  'ttf',
  'ttc',
  'txf',
  'dwg',
  'bat',
  'imazingapp',
  'dll',
  'crx',
  'xapk',
  'conf',
  'deb',
  'rp',
  'rpm',
  'rplib',
  'mobileconfig',
  'appimage',
  'lolgezi',
  'flac',
  'cad',
  'hwt',
  'accdb',
  'ce',
  'xmind',
  'enc',
  'bds',
  'bdi',
  'ssf',
  'it',
  'pkg',
  'cfg',
  'mp4',
  'avi',
  'png',
  'jpeg',
  'jpg',
  'gif',
  'webp',
  'brushset',
};

/// 从账号页面解析出的上传约束。
class LanzouUploadPolicy {
  const LanzouUploadPolicy({
    required this.maxFileBytes,
    required this.allowedExtensions,
  });

  static const fallback = LanzouUploadPolicy(
    maxFileBytes: kFallbackUploadLimitBytes,
    allowedExtensions: kFallbackUploadExtensions,
  );

  final int maxFileBytes;
  final Set<String> allowedExtensions;

  String get limitLabel => formatUploadSize(maxFileBytes);

  bool allowsFile(String name) {
    final extension = uploadExtensionOf(name);
    return extension.isNotEmpty && allowedExtensions.contains(extension);
  }
}

String uploadExtensionOf(String name) {
  final fileName = name.split(RegExp(r'[/\\]')).last;
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

String formatUploadSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final decimals = value == value.roundToDouble() ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}
