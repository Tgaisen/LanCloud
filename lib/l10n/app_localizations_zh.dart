// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get resolvingDownload => '正在解析下载地址…';

  @override
  String get addedToQueue => '已加入下载队列';

  @override
  String get shareNeedsPassword => '该文件需要提取码';

  @override
  String resolveFailed(String error) {
    return '解析失败：$error';
  }

  @override
  String get tabHome => '首页';

  @override
  String get tabDrive => '网盘';

  @override
  String get tabTransfers => '传输';

  @override
  String get tabProfile => '我的';

  @override
  String get exitTitle => '还有任务在进行';

  @override
  String exitMessage(int count) {
    return '当前有 $count 个传输任务，退出会终止它们，确定退出吗？';
  }

  @override
  String get keepTransferring => '继续传输';

  @override
  String get exitAndCancel => '终止并退出';

  @override
  String get download => '下载';

  @override
  String get copyLink => '复制链接';

  @override
  String linkWithPassword(String url, String pwd) {
    return '$url 提取码：$pwd';
  }

  @override
  String get notLoggedIn => '未登录';

  @override
  String accountUid(String uid) {
    return '账号 $uid';
  }

  @override
  String get openShareLink => '打开分享链接';

  @override
  String get scanComingSoonTooltip => '扫码（后续版本）';

  @override
  String get scanComingSoon => '扫码功能将在后续版本加入';

  @override
  String transferringCount(int count) {
    return '传输中 $count';
  }

  @override
  String get transferCenter => '传输中心';

  @override
  String get quickAccess => '快速访问';

  @override
  String get quickAccessHint => '可以在网盘页把常用文件夹固定到这里（后续版本）';

  @override
  String get recent => '最近使用';

  @override
  String get noRecent => '还没有最近使用的记录';

  @override
  String get sharedContent => '分享内容';

  @override
  String get myDrive => '我的网盘';

  @override
  String get myFavorites => '我的收藏';

  @override
  String get favoritesHint => '收藏的文件和分享会出现在这里';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get addAccount => '添加账号';

  @override
  String get lanCloudSubtitle => '蓝奏云第三方客户端';

  @override
  String get howToGetCookie => '如何获取 Cookie';

  @override
  String get cookieSteps =>
      '1. 用浏览器打开并登录蓝奏云官网\n2. 按 F12 打开开发者工具，切到 Network（网络）面板\n3. 随便点击一个请求，找到 Request Headers 里的 Cookie\n4. 复制整段内容（需包含 ylogin 和 phpdisk_info）';

  @override
  String get webLoginRecommended => '网页登录（推荐）';

  @override
  String get orPasteCookie => '或者手动粘贴 Cookie';

  @override
  String get lanzouCookie => '蓝奏云 Cookie';

  @override
  String get cookieHint => 'ylogin=1234567; phpdisk_info=xxxxxx...';

  @override
  String get verifying => '正在验证…';

  @override
  String get saveAndLogin => '保存并登录';

  @override
  String get cookiePrivacy => 'Cookie 只保存在你手机本地（系统加密存储），不会上传到任何第三方服务器。';

  @override
  String get pleasePasteCookie => '请先粘贴 Cookie';

  @override
  String get cookieMissingYlogin => '未找到 ylogin，请确认复制的是完整 Cookie';

  @override
  String get cookieInvalid => 'Cookie 无效或已过期，请重新获取';

  @override
  String get webLogin => '网页登录';

  @override
  String get checking => '检测中…';

  @override
  String get finishLogin => '完成登录';

  @override
  String get webLoginGuide => '请使用你的蓝奏云账号登录；遇到滑块验证正常完成即可。登录成功跳到网盘页面后会自动保存账号。';

  @override
  String get noLoginDetected => '还没有检测到登录状态，请先在上方页面完成登录';

  @override
  String get my => '我的';

  @override
  String uidLabel(String uid) {
    return 'UID: $uid';
  }

  @override
  String get switchAccountShort => '切换';

  @override
  String get switchAccount => '切换账号';

  @override
  String get removeCurrentAccount => '移除当前账号';

  @override
  String get settings => '设置';

  @override
  String get settingsSubtitle => '外观、行为、连接与高级覆盖项';

  @override
  String get webManagement => '网页版管理';

  @override
  String get webManagementSubtitle => '修改密码、头像等官方功能';

  @override
  String get recycleBin => '回收站';

  @override
  String get removeAccountTitle => '移除账号';

  @override
  String removeAccountMessage(String uid) {
    return '将从本机移除账号 $uid 及其登录信息，云端文件不受影响。';
  }

  @override
  String get cancel => '取消';

  @override
  String get remove => '移除';

  @override
  String get transfers => '传输管理';

  @override
  String get clearFinished => '清除已完成';

  @override
  String get upload => '上传';

  @override
  String get noUploads => '暂无上传任务';

  @override
  String get noDownloads => '暂无下载任务';

  @override
  String get inProgress => '进行中';

  @override
  String get finished => '已结束';

  @override
  String get queued => '排队中';

  @override
  String get uploading => '上传中';

  @override
  String get downloading => '下载中';

  @override
  String get completed => '已完成';

  @override
  String failedWithError(String error) {
    return '失败：$error';
  }

  @override
  String get unknownError => '未知错误';

  @override
  String get canceled => '已取消';

  @override
  String get unknownSize => '未知大小';

  @override
  String get retry => '重试';

  @override
  String get open => '打开';

  @override
  String get pleasePasteShareLink => '请先粘贴蓝奏云分享链接';

  @override
  String get addedToFavorites => '已加入收藏';

  @override
  String get openShare => '打开分享';

  @override
  String get shareLink => '分享链接';

  @override
  String get shareLinkHint => 'https://www.lanzou.com/xxxxx';

  @override
  String get passwordOptional => '提取码（如有）';

  @override
  String get resolving => '解析中…';

  @override
  String get resolve => '解析';

  @override
  String sizeLabel(String size) {
    return '大小：$size';
  }

  @override
  String get favorite => '收藏';

  @override
  String get shareEmpty => '这个分享里没有文件';

  @override
  String get language => '语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get themeMode => '深浅色模式';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get themeModeKeywords => '主题 夜间 深色 浅色';

  @override
  String get oled => 'OLED 纯黑';

  @override
  String get oledSubtitle => '深色模式下用纯黑背景，更省电';

  @override
  String get oledKeywords => '纯黑 省电 oled';

  @override
  String get themeColor => '主题色';

  @override
  String get themeColorKeywords => '配色 颜色 主题';

  @override
  String get classicBlue => '经典蓝';

  @override
  String get teal => '青绿';

  @override
  String get violet => '紫罗兰';

  @override
  String get vermilion => '朱红';

  @override
  String get olive => '橄榄绿';

  @override
  String get custom => '自定义';

  @override
  String get hideTopBar => '顶栏收起';

  @override
  String get hideTopBarSubtitle => '列表滑动时收起顶栏';

  @override
  String get hideTopBarKeywords => '顶栏 滑动隐藏 收起';

  @override
  String get hideBottomBar => '底栏收起';

  @override
  String get hideBottomBarSubtitle => '列表滑动时收起底栏';

  @override
  String get hideBottomBarKeywords => '底栏 滑动隐藏 收起';

  @override
  String get floatingNav => 'MD3 悬浮底栏';

  @override
  String get floatingNavSubtitle => '带圆角和阴影，浮在内容之上';

  @override
  String get floatingNavKeywords => '底栏 悬浮 md3';

  @override
  String get swipeTabs => '横滑切换视图';

  @override
  String get swipeTabsSubtitle => '左右滑动在首页/网盘/传输/我的之间切换';

  @override
  String get swipeTabsKeywords => '滑动 手势 tab';

  @override
  String get transitionAnimations => '过渡动画';

  @override
  String get transitionAnimationsSubtitle => '目录切换与列表出现时的淡入动画';

  @override
  String get transitionAnimationsKeywords => '动画 过渡 淡入 目录 列表';

  @override
  String get downloadDir => '下载目录';

  @override
  String get defaultDownloadDir => '默认（应用文档目录/LanCloud）';

  @override
  String get downloadDirKeywords => '下载 目录 保存位置';

  @override
  String get launchPage => '默认启动页';

  @override
  String get launchPageKeywords => '启动 首页 网盘';

  @override
  String get cacheFolders => '缓存目录数据';

  @override
  String get cacheFoldersSubtitle => '返回上一级时不再重新加载';

  @override
  String get cacheFoldersKeywords => '缓存 目录';

  @override
  String get loadAllPages => '自动加载全部目录内容';

  @override
  String get loadAllPagesSubtitle => '关闭时按页加载，滑到底部再加载下一页';

  @override
  String get loadAllPagesKeywords => '分页 加载 目录';

  @override
  String get requestInterval => '网络请求间隔';

  @override
  String requestIntervalSubtitle(int ms) {
    return '$ms ms（默认 300，过小可能触发限流）';
  }

  @override
  String get requestIntervalKeywords => '间隔 限流 风控 请求';

  @override
  String get maxUploads => '同时上传数量';

  @override
  String get uploadKeywords => '上传 并发';

  @override
  String get maxDownloads => '同时下载数量';

  @override
  String get downloadKeywords => '下载 并发';

  @override
  String get apiHost => '网盘接口域名';

  @override
  String get apiHostKeywords => '域名 接口 连接异常 pc up';

  @override
  String get uploadDomain => '上传域名';

  @override
  String get defaultUploadDomain => '默认（up.woozooo.com）';

  @override
  String get uploadDomainKeywords => '上传 域名 up';

  @override
  String get shareDomain => '分享链接域名';

  @override
  String get defaultShareDomain => '默认（自动尝试内置镜像）';

  @override
  String get shareDomainKeywords => '分享 域名 镜像 链接';

  @override
  String get userAgent => '自定义 User-Agent';

  @override
  String get defaultUserAgent => '默认（模拟桌面浏览器）';

  @override
  String get userAgentKeywords => 'ua user-agent 浏览器';

  @override
  String get advanced => '高级覆盖项';

  @override
  String get advancedSubtitle => '接口/上传/分享域名与自定义 UA';

  @override
  String get advancedHint => '仅在连接异常或域名被墙时修改，留空恢复默认';

  @override
  String get clearRecents => '清空最近使用记录';

  @override
  String get clearRecentsSubtitle => '删除首页最近使用条目';

  @override
  String get clearRecentsKeywords => '最近 清空 记录';

  @override
  String get about => '关于';

  @override
  String get aboutSubtitle => 'LanCloud · 蓝奏云第三方客户端';

  @override
  String get aboutKeywords => '版本 关于 开源 协议';

  @override
  String get aboutText => '自用的蓝奏云第三方客户端，基于非官方接口实现，请勿传播或用于商业用途。';

  @override
  String get searchSettings => '搜索设置';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get searchPlaceholder => '输入关键词搜索设置，如：域名、收起、下载、并发';

  @override
  String get noMatch => '没有匹配的设置项';

  @override
  String get cleared => '已清空';

  @override
  String get restoredDefaultDir => '已恢复默认目录';

  @override
  String get restoreDefault => '恢复默认';

  @override
  String get change => '更改';

  @override
  String downloadDirSet(String dir) {
    return '下载目录已设为 $dir';
  }

  @override
  String pickDirFailed(String error) {
    return '选择目录失败：$error';
  }

  @override
  String get noInterval => '不间隔';

  @override
  String get save => '保存';

  @override
  String get uploadDomainHint => '留空使用默认 up.woozooo.com，可带 https://';

  @override
  String get shareDomainHint => '留空自动尝试内置镜像，可带 https://';

  @override
  String get userAgentHint => '留空表示使用默认值';

  @override
  String get categoryAppearance => '外观';

  @override
  String get categoryBehavior => '行为';

  @override
  String get categoryConnection => '连接';

  @override
  String get categoryAdvanced => '高级覆盖项';

  @override
  String get categoryData => '数据';

  @override
  String get exitSelection => '退出多选';

  @override
  String selectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get selectAll => '全选';

  @override
  String get invertSelection => '反选';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get uploadFile => '上传文件';

  @override
  String get uploadFileSubtitle => '从本机或其他应用中选择文件';

  @override
  String uploadSkipped(int added, int skipped) {
    return '已加入 $added 个上传任务，跳过 $skipped 个超过 100MB 的文件';
  }

  @override
  String uploadAdded(int count) {
    return '已加入 $count 个上传任务';
  }

  @override
  String get nameRequired => '名称（必填）';

  @override
  String get descOptional => '简介（选填）';

  @override
  String get create => '创建';

  @override
  String get folderNameRequired => '文件夹名称不能为空';

  @override
  String get deleteConfirmTitle => '删除确认';

  @override
  String deleteConfirmMessage(int count) {
    return '将把选中的 $count 个条目移入回收站，继续吗？';
  }

  @override
  String get delete => '删除';

  @override
  String get batchDownload => '批量下载';

  @override
  String resolvingBatch(int count) {
    return '正在解析并加入下载队列（共 $count 个）';
  }

  @override
  String addedDownloads(int count) {
    return '已加入 $count 个下载任务';
  }

  @override
  String addedDownloadsPartial(int ok, int failed) {
    return '已加入 $ok 个下载任务，$failed 个解析失败';
  }

  @override
  String get noLinksToCopy => '没有可复制的分享链接';

  @override
  String passwordLabel(String pwd) {
    return '提取码：$pwd';
  }

  @override
  String favoritedCount(int count) {
    return '已收藏 $count 个条目';
  }

  @override
  String get move => '移动';

  @override
  String get moveSubtitle => '把选中的文件/文件夹移动到其他目录';

  @override
  String get editDesc => '修改简介';

  @override
  String get editDescBatchSubtitle => '批量设置选中的文件/文件夹简介';

  @override
  String get setPassword => '设置访问密码';

  @override
  String get setPasswordSubtitle => '批量设置选中条目的访问密码；免费账号只能设置不能关闭';

  @override
  String movedTo(int count, String name) {
    return '已移动 $count 个条目到「$name」';
  }

  @override
  String movedPartial(int ok, int failed) {
    return '已移动 $ok 个条目，$failed 个失败';
  }

  @override
  String get newDescHint => '输入新的简介';

  @override
  String get confirm => '确定';

  @override
  String descUpdatedCount(int count) {
    return '已修改 $count 个条目的简介';
  }

  @override
  String descUpdatedPartial(int ok, int failed) {
    return '已修改 $ok 个，$failed 个失败';
  }

  @override
  String get pwdHint => '2-6 位提取码';

  @override
  String get pwdTooShort => '提取码至少 2 位';

  @override
  String passwordSetCount(int count) {
    return '已为 $count 个条目设置提取码';
  }

  @override
  String passwordSetPartial(int ok, int failed) {
    return '已设置 $ok 个，$failed 个失败';
  }

  @override
  String get close => '关闭';

  @override
  String downloadsCount(int count) {
    return '下载 $count';
  }

  @override
  String get hasPassword => '有提取码';

  @override
  String get openLink => '打开链接';

  @override
  String get showQr => '显示二维码';

  @override
  String get addFavorite => '添加收藏';

  @override
  String get moreActions => '更多操作';

  @override
  String get freeAccountPasswordNote => '免费账号只能设置不能关闭';

  @override
  String get descUpdated => '简介已更新';

  @override
  String get passwordSet => '已设置提取码';

  @override
  String get favorited => '已收藏';

  @override
  String get share => '分享';

  @override
  String get more => '更多';

  @override
  String get add => '添加';

  @override
  String get searchCurrentFolder => '搜索当前目录';

  @override
  String get search => '搜索';

  @override
  String get menu => '菜单';

  @override
  String get sortByName => '按名称排序';

  @override
  String get sortBySize => '按大小排序';

  @override
  String get sortByTime => '按时间排序';

  @override
  String get toggleLayout => '切换布局样式';

  @override
  String get multiSelect => '多选';

  @override
  String get refresh => '刷新';

  @override
  String get root => '根目录';

  @override
  String loadFailed(String error) {
    return '加载失败：$error';
  }

  @override
  String noMatchContent(String query) {
    return '没有匹配「$query」的内容';
  }

  @override
  String get emptyFolder => '这个文件夹是空的';

  @override
  String get reachedEnd => '已经到底了';

  @override
  String get filterResult => '筛选结果';

  @override
  String get folderActions => '文件夹操作';

  @override
  String get fileActions => '文件操作';

  @override
  String get downloaded => '已下载';

  @override
  String get folder => '文件夹';

  @override
  String fileCount(int count) {
    return '$count 个文件';
  }

  @override
  String get openFolder => '打开文件夹';

  @override
  String get chooseTargetFolder => '选择目标文件夹';

  @override
  String get parentFolder => '上一级';

  @override
  String get moveHere => '移动到这里';

  @override
  String get noSubfolders => '这个文件夹里没有子文件夹';
}
