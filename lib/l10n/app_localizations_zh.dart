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
  String get quickAccessHint => '可在此固定常用网盘目录';

  @override
  String get recent => '最近使用';

  @override
  String get noRecent => '还没有最近使用的记录';

  @override
  String get sharedContent => '分享内容';

  @override
  String get myDrive => '我的网盘';

  @override
  String get myFavorites => '收藏';

  @override
  String get favoritesHint => '收藏的文件和分享会出现在这里';

  @override
  String get favoriteFolders => '文件夹';

  @override
  String get favoriteFiles => '文件';

  @override
  String get favoriteDeleteConfirmTitle => '删除收藏';

  @override
  String favoriteDeleteConfirmMessage(int count) {
    return '将移除选中的 $count 个收藏，继续吗？';
  }

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
  String get webManagement => '网页版';

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
  String get transfers => '传输';

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
  String get openShare => '打开链接';

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
  String get homeFolderOpen => '首页目录打开方式';

  @override
  String get homeFolderOpenKeywords => '首页 目录 打开方式 新页面 网盘';

  @override
  String get openInNewPage => '新页面';

  @override
  String get openInDriveTab => '网盘页';

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
  String get folderInfo => '修改信息';

  @override
  String get folderInfoSubtitle => '修改名称与简介';

  @override
  String get accessPassword => '访问密码';

  @override
  String get accessPasswordSubtitle => '可设置或关闭访问密码';

  @override
  String get enablePassword => '启用访问密码';

  @override
  String get folderInfoSaved => '文件夹信息已更新';

  @override
  String get passwordCleared => '已关闭访问密码';

  @override
  String passwordClearedCount(int count) {
    return '已关闭 $count 项的访问密码';
  }

  @override
  String get transferDeleteConfirmTitle => '删除传输记录';

  @override
  String transferDeleteConfirmMessage(int count) {
    return '将移除选中的 $count 条记录（进行中的会先取消），继续吗？';
  }

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
  String get layout => '布局';

  @override
  String get grid => '网格';

  @override
  String get list => '列表';

  @override
  String get sort => '排序';

  @override
  String get sortName => '名称';

  @override
  String get sortSize => '大小';

  @override
  String get sortTime => '时间';

  @override
  String get folderProperties => '目录属性';

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
  String get moveHere => '移动到此';

  @override
  String get noSubfolders => '这个文件夹里没有子文件夹';

  @override
  String get notifications => '通知';

  @override
  String get notifProgress => '传输进度通知';

  @override
  String get notifProgressSubtitle => '传输进行中在通知栏显示进度';

  @override
  String get notifProgressKeywords => '通知 进度 传输';

  @override
  String get notifDone => '传输完成提醒';

  @override
  String get notifDoneSubtitle => '下载或上传完成、失败时提醒';

  @override
  String get notifDoneKeywords => '通知 完成 提醒';

  @override
  String get notifPermission => '通知权限';

  @override
  String get notifPermissionKeywords => '通知 权限 授权';

  @override
  String get notifPermissionChecking => '检查中…';

  @override
  String get notifPermissionGranted => '已授权';

  @override
  String get notifPermissionDenied => '未授权';

  @override
  String get notifPermissionDeniedHint => '通知权限未开启，请到系统设置中允许通知';

  @override
  String get notifProgressTitle => '传输中';

  @override
  String notifProgressBody(int count) {
    return '$count 个任务进行中';
  }

  @override
  String get notifUploadDone => '上传完成';

  @override
  String get notifDownloadDone => '下载完成';

  @override
  String get notifFailed => '传输失败';

  @override
  String get notifChannelProgress => '传输进度';

  @override
  String get notifChannelProgressDesc => '下载与上传进行中的进度';

  @override
  String get notifChannelDone => '传输完成';

  @override
  String get notifChannelDoneDesc => '下载与上传完成或失败的提醒';

  @override
  String get files => '文件';

  @override
  String get shareMessage => '来自分享者的信息';

  @override
  String favoritedPartial(int ok, int failed) {
    return '$ok 个已收藏，$failed 个失败';
  }

  @override
  String get file => '文件';

  @override
  String sharerLabel(String name) {
    return '分享者 $name';
  }

  @override
  String get editInfo => '修改信息';

  @override
  String get favoriteTitle => '自定义标题';

  @override
  String get favoriteTitleHint => '留空则使用默认名称';

  @override
  String get shareInvalid => '该分享已失效（已取消或删除）';

  @override
  String get manage => '管理';

  @override
  String get logout => '退出登录';

  @override
  String get appName => '蓝云';

  @override
  String shareReceivedFiles(int count) {
    return '已接收 $count 个文件，开始上传';
  }

  @override
  String get shareTargetUnsupported => '无法识别的分享内容';

  @override
  String get uploadHere => '上传到此';

  @override
  String get uploadFromApp => '从应用上传';

  @override
  String uploadTasksAdded(int count) {
    return '已加入 $count 个上传任务';
  }

  @override
  String get install => '安装';

  @override
  String notifDoneCount(int count) {
    return '已完成 $count 个';
  }

  @override
  String get addToQuickAccess => '添加到快速访问';

  @override
  String get removeFromQuickAccess => '从快速访问移除';

  @override
  String get unpin => '取消固定';

  @override
  String get moveToTop => '移到顶部';

  @override
  String get expand => '展开';

  @override
  String get collapse => '收起';

  @override
  String get copy => '复制';

  @override
  String get continueLabel => '继续';

  @override
  String get showCookie => '显示 Cookie';

  @override
  String get showCookieSubtitle => '需通过生物识别 / 锁屏验证';

  @override
  String get cookieRiskTitle => '显示 Cookie？';

  @override
  String get cookieRiskMessage =>
      'Cookie 等同于账号登录凭据，任何拿到它的人都能直接登录并操作你的网盘。请勿截图、转发或粘贴到不可信的设备与应用中。';

  @override
  String get cookieAuthReason => '验证身份后显示 Cookie';

  @override
  String get cookieAuthFailed => '身份验证未通过，已取消显示';

  @override
  String get cookieAuthUnavailable => '当前设备未设置锁屏密码或生物识别，无法验证身份';

  @override
  String get cookieSheetTitle => '账号 Cookie';

  @override
  String get cookieExport => '导出';

  @override
  String get cookieExportFailed => '导出失败';

  @override
  String get categoryPermissions => '权限';

  @override
  String get permissionCamera => '相机（扫码）';

  @override
  String get permissionCameraKeywords => 'camera qr scan 相机 扫码 权限';

  @override
  String get permissionInstall => '安装应用（打开 APK）';

  @override
  String get permissionInstallKeywords =>
      'install apk unknown sources 安装 未知来源 权限';

  @override
  String get permissionBattery => '电池优化';

  @override
  String get permissionBatteryKeywords =>
      'battery optimization background 电池 优化 后台 权限';

  @override
  String get permissionGranted => '已授权';

  @override
  String get permissionDenied => '未授权，点击授权';

  @override
  String get permissionBlocked => '已被系统拒绝，需到系统设置开启';

  @override
  String get permissionChecking => '检查中…';

  @override
  String get permissionInstallGranted => '已允许安装应用';

  @override
  String get permissionInstallDenied => '未允许，打开 APK 安装包前需授权';

  @override
  String get permissionBatteryGranted => '已忽略电池优化，后台传输更稳定';

  @override
  String get permissionBatteryRestricted => '受电池优化限制，后台传输可能被中断';

  @override
  String get permissionBlockedTitle => '需要到系统设置开启';

  @override
  String get permissionBlockedMessage => '相机权限已被系统拒绝，请到系统设置中手动开启，然后回到应用。';

  @override
  String get permissionOpenSystemSettings => '打开系统设置';

  @override
  String get permissionCameraGranted => '相机权限已授权';

  @override
  String get permissionOpenFailed => '无法打开系统设置';

  @override
  String get backupAndRestore => '备份与恢复';

  @override
  String get backupAndRestoreSubtitle => '本地文件与 WebDAV 云端';

  @override
  String get backupKeywords => 'backup restore webdav cookie 备份 恢复 云端 导出';

  @override
  String get localBackup => '本地备份';

  @override
  String get backupNow => '立即备份';

  @override
  String get backupNowSubtitle => '导出为 JSON 备份文件';

  @override
  String backupSaved(String path) {
    return '已保存到 $path';
  }

  @override
  String get restoreFromFile => '从文件恢复';

  @override
  String get restoreFromFileSubtitle => '选择之前导出的备份文件';

  @override
  String get chooseBackupFile => '选择备份文件';

  @override
  String get includeCookies => '备份包含 Cookie';

  @override
  String get includeCookiesSubtitle => '默认不含；包含后备份文件等同于账号凭据';

  @override
  String get webdavSection => 'WebDAV';

  @override
  String get webdavServer => 'WebDAV 地址';

  @override
  String get webdavServerHint => 'https://example.com/dav/';

  @override
  String get webdavUsername => '用户名';

  @override
  String get webdavPassword => '密码';

  @override
  String get webdavNotSet => '未设置';

  @override
  String get webdavBackup => '云端备份';

  @override
  String get webdavTest => '测试连接';

  @override
  String get webdavTestOk => '连接成功';

  @override
  String get webdavUpload => '上传备份';

  @override
  String webdavUploadDone(String name) {
    return '已上传 $name';
  }

  @override
  String get webdavRestore => '从云端恢复';

  @override
  String get webdavNoBackups => '云端还没有备份文件';

  @override
  String get webdavAutoBackup => '自动备份';

  @override
  String get webdavAutoBackupSubtitle => '启动应用时按频率自动上传';

  @override
  String get webdavInterval => '备份频率';

  @override
  String get webdavDaily => '每天';

  @override
  String get webdavWeekly => '每周';

  @override
  String lastBackupAt(String time) {
    return '上次备份：$time';
  }

  @override
  String get neverBackedUp => '尚未备份';

  @override
  String backupFailed(String error) {
    return '上次备份失败：$error';
  }

  @override
  String get restoreConfirmTitle => '从备份恢复？';

  @override
  String get restoreConfirmMessage => '将覆盖当前设置、收藏、最近使用与快速访问；账号登录态与传输记录会保留。';

  @override
  String get restoreDone => '已从备份恢复';

  @override
  String aboutVersion(String version, int build) {
    return '版本 $version（构建 $build）';
  }

  @override
  String get aboutTerms => '用户协议';

  @override
  String get aboutPrivacy => '隐私政策';

  @override
  String get aboutLicenses => '开源许可';

  @override
  String get aboutProjectHome => '项目主页';

  @override
  String get aboutCopyright => '© 2026 Tgaisen · Apache License 2.0';

  @override
  String get termsDisclaimer =>
      '7. 免责声明：本应用是非官方的蓝奏云第三方客户端，与蓝奏云官方无任何关联，也未获得官方授权。应用按「现状」提供，因使用本应用造成的账号风险、数据丢失或服务中断由使用者自行承担。';

  @override
  String get firstRunWelcome => '欢迎使用蓝云';

  @override
  String get firstRunMessage => '使用前请阅读并同意《用户协议》与《隐私政策》。应用不收集个人信息，账号与数据只保存在本机。';

  @override
  String get agreeAndContinue => '同意并继续';

  @override
  String get disagreeAndExit => '不同意并退出';

  @override
  String get recentLimit => '最近使用条数';

  @override
  String get recentLimitOff => '不记录';

  @override
  String recentLimitValue(int count) {
    return '$count 条';
  }

  @override
  String get recentLimitKeywords => 'recent limit history 最近 条数 记录';

  @override
  String get termsBody =>
      '《用户协议》\n\n1. 本应用是蓝奏云的非官方第三方客户端，仅供个人学习与自用，与蓝奏云官方无任何关联，也未获得官方授权或认可。\n\n2. 使用本应用需要你自己的蓝奏云账号。请勿利用本应用从事违反蓝奏云服务条款、相关法律法规或侵犯他人权益的行为。\n\n3. 本应用按「现状」提供，不提供任何形式的担保。因使用本应用造成的账号受限、数据丢失、上传或下载失败等风险，由使用者自行承担。\n\n4. 应用内使用的接口来自公开渠道与非官方整理，可能随时失效；开发者不保证功能持续可用。\n\n5. 本应用以 Apache License 2.0 开源，你可以自行修改与分发代码，但请保留原始许可与版权声明，并自行承担由此产生的责任。\n\n6. 继续使用即表示你已阅读并同意本协议；如不同意，请卸载本应用。';

  @override
  String get privacyBody =>
      '《隐私政策》\n\n1. 本应用不收集、不上传任何个人信息，没有账号系统，也没有统计、广告或崩溃上报 SDK。\n\n2. 你的蓝奏云账号（Cookie）、昵称、收藏、最近使用、传输记录与设置只保存在本机。Cookie 保存在系统加密存储中；查看 Cookie 需要先通过生物识别或锁屏验证。\n\n3. 应用运行时直接与蓝奏云官方接口通信（pc.woozooo.com、up.woozooo.com 等），请求内容仅用于完成你发起的登录、列表、上传、下载等操作。\n\n4. 分享由系统分享面板完成：只有你主动点击分享时，选中的内容或文件才会交给你选择的应用；剪贴板仅在你主动点击「复制」时写入。\n\n5. 如果你在「备份与恢复」中配置了 WebDAV，备份文件会上传到你自己填写的服务器；备份默认不包含 Cookie，是否开启与上传到哪台服务器完全由你决定。\n\n6. 相机权限仅用于扫码（当前版本尚未启用），安装应用权限仅用于打开你下载的 APK，忽略电池优化仅用于让后台传输更稳定；这些权限都可以随时在系统设置中撤销。\n\n7. 卸载应用会一并删除本机保存的账号与数据，删除前请自行备份。';
}
