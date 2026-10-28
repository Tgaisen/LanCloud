import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/download_dir.dart';

void main() {
  const privateRoot =
      '/storage/emulated/0/Android/data/com.lancloud.lancloud/files';
  const publicRoot = '/storage/emulated/0';

  DownloadDirKind kind(String path) => classifyDownloadDir(
    path,
    privateRoots: const [privateRoot],
    publicRoot: publicRoot,
  );

  test('私有目录：默认下载目录及其所属的应用专属根', () {
    expect(kind('$privateRoot/LanCloud'), DownloadDirKind.privateDir);
    expect(kind(privateRoot), DownloadDirKind.privateDir);
  });

  test('公共目录：Download、Documents 及其子目录', () {
    expect(kind('$publicRoot/Download'), DownloadDirKind.publicDir);
    expect(kind('$publicRoot/Download/LanCloud'), DownloadDirKind.publicDir);
    expect(kind('$publicRoot/Documents'), DownloadDirKind.publicDir);
    expect(kind('$publicRoot/DCIM/相册'), DownloadDirKind.publicDir);
  });

  test('非公共目录：标准公共目录之外的路径（如 BaiduNetdisk）', () {
    expect(kind('$publicRoot/BaiduNetdisk'), DownloadDirKind.customDir);
    // 名字带公共目录前缀、但不是标准目录
    expect(kind('$publicRoot/Pictures2'), DownloadDirKind.customDir);
    expect(kind('$publicRoot/Downloading'), DownloadDirKind.customDir);
  });

  test('publicStorageRootFrom：从默认目录推出外部存储根', () {
    expect(publicStorageRootFrom('$privateRoot/LanCloud'), publicRoot);
    expect(publicStorageRootFrom('$publicRoot/Download/LanCloud'), publicRoot);
    expect(
      publicStorageRootFrom('/storage/1234-5678/Download/LanCloud'),
      '/storage/1234-5678',
    );
    expect(
      publicStorageRootFrom('/data/user/0/com.lancloud.lancloud/app_flutter'),
      isNull,
    );
  });

  test('新版默认目录能判定为公共目录', () {
    const defaultPath = '$publicRoot/Download/LanCloud';
    final root = publicStorageRootFrom(defaultPath);
    expect(
      classifyDownloadDir(
        defaultPath,
        privateRoots: const [privateRoot],
        publicRoot: root,
      ),
      DownloadDirKind.publicDir,
    );
  });
}
