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
  String get shareNeedsPassword => '该分享需要提取码';

  @override
  String get wrongPassword => '提取码错误';

  @override
  String get lanzouInvalidResponse => '接口返回格式异常';

  @override
  String get lanzouCreateFolderFailed => '新建文件夹失败';

  @override
  String get lanzouDeleteFailed => '删除失败';

  @override
  String get lanzouMoveFileFailed => '移动文件失败';

  @override
  String get lanzouMoveToCurrentFolder => '不能移动到当前目录';

  @override
  String get lanzouMoveFolderWithSubfoldersUnsupported => '暂不支持移动含子文件夹的目录';

  @override
  String get lanzouReadFolderInfoFailed => '无法读取文件夹信息';

  @override
  String get lanzouSameTargetFolder => '目标位置与当前位置相同';

  @override
  String get lanzouUpdateDescriptionFailed => '修改简介失败';

  @override
  String get lanzouFileNameRequired => '文件名不能为空';

  @override
  String get lanzouRenameRequiresMembership => '重命名失败：此功能需要开通会员';

  @override
  String get lanzouUpdateFilePasswordFailed => '设置访问密码失败';

  @override
  String get lanzouFolderNameRequired => '文件夹名称不能为空';

  @override
  String get lanzouUpdateFolderInfoFailed => '保存文件夹信息失败';

  @override
  String get lanzouUpdateFolderPasswordFailed => '设置文件夹访问密码失败';

  @override
  String get lanzouUploadContentMissing => '没有可上传的文件内容';

  @override
  String lanzouUploadFailed(String detail) {
    return '上传失败：$detail';
  }

  @override
  String get lanzouUnknownError => '未知错误';

  @override
  String get lanzouFileShareInfoFailed => '无法获取该文件的分享信息';

  @override
  String get lanzouFolderShareInfoFailed => '获取文件夹分享信息失败';

  @override
  String lanzouResolveShareFailed(String detail) {
    return '解析分享失败：$detail';
  }

  @override
  String get lanzouFileShareUnavailable => '文件不存在或已取消分享';

  @override
  String get lanzouPasswordParameterParseFailed => '提取码参数解析失败';

  @override
  String get lanzouDownloadParameterParseFailed => '下载参数解析失败';

  @override
  String lanzouDownloadUrlFailed(String detail) {
    return '获取下载地址失败：$detail';
  }

  @override
  String get lanzouDirectLinkMissing => '未获取到直链';

  @override
  String get lanzouFolderShareUnavailable => '文件夹不存在或已取消分享';

  @override
  String get lanzouSharePageParseFailed => '分享页结构解析失败';

  @override
  String get lanzouShareFileListFailed => '获取分享文件列表失败';

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
  String get accountTitle => '账号';

  @override
  String get openShareLink => '打开分享链接';

  @override
  String transferringCount(int count) {
    return '传输中 $count';
  }

  @override
  String get transferCenter => '传输';

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
  String get favoritesHint => '暂无收藏内容';

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
  String get webLoginRecommended => '使用网页登录（推荐）';

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
  String get cookiePrivacy => 'Cookie 只保存在本地（系统加密存储），不会上传到任何第三方服务器。';

  @override
  String get pleasePasteCookie => '请输入 Cookie';

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
  String get webLoginGuide => '请在网页中登录蓝奏云账号；登录完成后会自动跳到网盘页面，或点按右上角“完成登录”进行手动检测。';

  @override
  String get noLoginDetected => '还没有检测到登录状态，请先在网页完成登录';

  @override
  String get my => '我的';

  @override
  String uidLabel(String uid) {
    return '账号: $uid';
  }

  @override
  String get switchAccountShort => '切换';

  @override
  String get switchAccount => '切换账号';

  @override
  String get removeCurrentAccount => '移除当前账号';

  @override
  String get accountManagement => '账号管理';

  @override
  String get appSection => '应用';

  @override
  String get settings => '设置';

  @override
  String get settingsSubtitle => '外观、行为、连接与高级覆盖项';

  @override
  String get webManagement => '网页版';

  @override
  String get webManagementSubtitle => '修改密码、头像等官方功能';

  @override
  String get userCenter => '个人中心';

  @override
  String get recycleBin => '回收站';

  @override
  String get removeAccountTitle => '移除账号';

  @override
  String removeAccountMessage(String uid) {
    return '将从本机移除账号 $uid 及其登录信息，云端文件不受影响。';
  }

  @override
  String get clearUsageData => '清除使用数据';

  @override
  String get clearUsageDataSubtitle => '清除此账号相关数据，如快速访问、最近使用';

  @override
  String get cancel => '取消';

  @override
  String get remove => '移除';

  @override
  String get clear => '清除';

  @override
  String get transfers => '传输';

  @override
  String get clearFinished => '清除已完成';

  @override
  String get clearFinishedConfirmTitle => '清除已完成记录';

  @override
  String get clearFinishedConfirmMessage => '将清除已完成的传输记录，继续吗？';

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
  String get cancelDownload => '取消下载';

  @override
  String get redownload => '重新下载';

  @override
  String get deleteDownloadRecord => '删除下载记录';

  @override
  String get waitingToDownload => '等待中';

  @override
  String get downloadFailed => '下载失败';

  @override
  String get batchRetry => '批量重试';

  @override
  String get taskInterrupted => '应用已退出，任务中断';

  @override
  String get retryUnavailable => '应用重启后请重新发起下载';

  @override
  String get retryUploadUnavailable => '应用重启后无法继续该上传，请重新上传';

  @override
  String get retryUploadFileGone => '源文件已不存在，请重新选择文件上传';

  @override
  String get uploadNeedLogin => '请先登录后再上传';

  @override
  String get retryResolving => '正在重新解析下载链接…';

  @override
  String retryResolveFailed(String error) {
    return '重新解析下载链接失败：$error';
  }

  @override
  String get networkError => '网络错误';

  @override
  String networkErrorHttp(int status) {
    return '网络错误（HTTP $status）';
  }

  @override
  String get downloadBlocked => '下载被风控拦截，请稍后重试';

  @override
  String get open => '打开';

  @override
  String get view => '查看';

  @override
  String get pleasePasteShareLink => '请输入分享链接';

  @override
  String get shareLinkFormatError => '分享链接格式错误';

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
  String get folderNeedsPassword => '此文件夹需要密码';

  @override
  String get fileNeedsPassword => '此文件需要密码';

  @override
  String get passwordFieldLabel => '提取码';

  @override
  String get passwordRequired => '请输入提取码';

  @override
  String get resolving => '解析中';

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
  String get system => '系统';

  @override
  String get chinese => '简体中文';

  @override
  String get english => 'English';

  @override
  String get themeMode => '主题模式';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get themeModeKeywords => '主题 夜间 深色 浅色';

  @override
  String get oled => '纯黑深色主题';

  @override
  String get oledSubtitle => '深色模式下用纯黑背景，更省电';

  @override
  String get oledKeywords => '纯黑 省电 oled';

  @override
  String get themeColor => '主题色';

  @override
  String get themeSeedDynamicHint => '启用动态取色时不生效';

  @override
  String get themeColorKeywords => '配色 颜色 主题';

  @override
  String get classicBlue => '默认蓝';

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
  String get colorMd3Purple => '经典紫';

  @override
  String get colorRoyalBlue => '宝蓝';

  @override
  String get colorRose => '玫红';

  @override
  String get colorAmber => '琥珀';

  @override
  String get hideTopBar => '滑动时收起顶栏';

  @override
  String get hideTopBarKeywords => '顶栏 滑动隐藏 收起';

  @override
  String get hideBottomBar => '滑动时收起底栏';

  @override
  String get hideBottomBarKeywords => '底栏 滑动隐藏 收起';

  @override
  String get floatingNav => '悬浮底栏';

  @override
  String get floatingNavSubtitle => '带圆角和阴影，浮在内容之上';

  @override
  String get floatingNavKeywords => '底栏 悬浮 md3';

  @override
  String get navBarItems => '底栏显示项';

  @override
  String get navBarItemsHint => '未勾选的视图不显示在底栏，仍可从首页快捷操作栏打开';

  @override
  String get navBarItemsKeywords => '底栏 显示项 传输 收藏 自定义';

  @override
  String get swipeTabs => '横滑切换视图';

  @override
  String get swipeTabsSubtitle => '左右横滑切换主页视图';

  @override
  String get swipeTabsKeywords => '滑动 手势 tab';

  @override
  String get transitionAnimations => '目录过渡动画';

  @override
  String get transitionAnimationsSubtitle => '目录切换的淡入动画';

  @override
  String get transitionAnimationsKeywords => '动画 过渡 淡入 目录 列表';

  @override
  String get downloadDir => '下载目录';

  @override
  String defaultDownloadDir(String path) {
    return '默认（$path）';
  }

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
    return '$ms ms';
  }

  @override
  String get requestIntervalHint => '间隔过小易触发服务器限流';

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
  String get uploadPath => '上传接口路径';

  @override
  String get uploadPathKeywords => '上传 接口 路径 域名 up html5up fileup';

  @override
  String get userAgent => '自定义 User-Agent';

  @override
  String get defaultUserAgent => '默认（模拟桌面浏览器）';

  @override
  String get userAgentKeywords => 'ua user-agent 浏览器';

  @override
  String get advanced => '高级覆盖项';

  @override
  String get advancedSubtitle => '接口/上传路径与自定义 UA';

  @override
  String get advancedHint => '正常情况下不宜更改这些选项，否则可能导致相关功能故障';

  @override
  String get clearData => '清除数据';

  @override
  String get clearDataKeywords => '清除 数据 快速访问 最近 日志 注册表';

  @override
  String get clearDataGroupAccount => '此账号';

  @override
  String get clearDataGroupOthers => '其他数据';

  @override
  String get clearDataOtherAccounts => '其他账号数据';

  @override
  String get clearDataOtherAccountsSubtitle => '其他账号的相关数据，如快速访问、最近使用';

  @override
  String get clearDataLogs => '运行日志';

  @override
  String get clearDataRegistry => '注册表项目';

  @override
  String get clearDataRegistrySubtitle => '为显示系统通知图标而创建的注册表项';

  @override
  String get clearCache => '清理缓存';

  @override
  String get clearCacheSubtitle => '删除临时文件与图片缓存，不影响账号和已下载的文件';

  @override
  String get clearCacheKeywords => '缓存 清理 空间 临时';

  @override
  String clearCacheBody(String size) {
    return '当前占用 $size。将删除临时文件、图片缓存和目录列表缓存，账号、设置与已下载的文件不受影响。';
  }

  @override
  String get clearCacheBodyUnknown => '将删除临时文件、图片缓存和目录列表缓存，账号、设置与已下载的文件不受影响。';

  @override
  String get clean => '清理';

  @override
  String cacheCleared(String size) {
    return '已清理 $size';
  }

  @override
  String get about => '关于';

  @override
  String get aboutSubtitle => 'LanCloud · 蓝奏云第三方客户端';

  @override
  String get aboutKeywords => '版本 关于 开源 协议';

  @override
  String get aboutText => '自用的蓝奏云第三方客户端，基于非官方接口实现，请勿传播或用于商业用途。';

  @override
  String get searchSettings => '搜索设置项';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get searchPlaceholder => '支持输入关键词搜索';

  @override
  String get noMatch => '没有匹配的设置项';

  @override
  String get searchOtherSettings => '其他设置项';

  @override
  String get cleared => '已清空';

  @override
  String get clearDataNothingSelected => '未选择清除项';

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
  String privateDownloadDir(String path) {
    return '私有目录（$path）';
  }

  @override
  String publicDownloadDir(String path) {
    return '公共目录（$path）';
  }

  @override
  String customDownloadDir(String path) {
    return '非公共目录（$path）';
  }

  @override
  String get downloadDirHint =>
      'Android 10 及以上默认下载到公共目录 Download/LanCloud，无需存储权限或目录授权；Android 9 及以下受系统限制，默认下载到应用私有目录。如需更改位置，建议选择系统公共目录；选择非公共目录需下载完成后二次移入。';

  @override
  String get safDirPermissionLost => '下载目录授权已失效，请在设置里重新选择下载目录';

  @override
  String safExportFailed(String error) {
    return '写入下载目录失败：$error';
  }

  @override
  String get noInterval => '不间隔';

  @override
  String get save => '保存';

  @override
  String get reset => '重置';

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
  String get categoryAppearanceLayout => '外观与布局';

  @override
  String get categoryBehaviorPermissions => '行为与权限';

  @override
  String get categoryNotificationsReminders => '通知与提醒';

  @override
  String get categoryTransferConnection => '传输与连接';

  @override
  String get categoryPrivacyData => '隐私与数据';

  @override
  String get sectionLayout => '布局';

  @override
  String get sectionReminder => '提醒';

  @override
  String get sectionDownload => '下载';

  @override
  String get sectionUpload => '上传';

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
  String get nameLabel => '名称';

  @override
  String get nameLabelMember => '名称（修改名称需开通会员）';

  @override
  String get pleaseEnterName => '请输入名称';

  @override
  String get descOptional => '简介（选填）';

  @override
  String get create => '创建';

  @override
  String get folderNameRequired => '文件夹名称不能为空';

  @override
  String get nameRequired => '名称不能为空';

  @override
  String get deleteConfirmTitle => '删除确认';

  @override
  String deleteConfirmMessage(int count) {
    return '将把选中的 $count 个条目移入回收站，继续吗？';
  }

  @override
  String deleteConfirmSingle(String name) {
    return '将把「$name」移入回收站，继续吗？';
  }

  @override
  String get deleteRecord => '删除此条记录';

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
  String get folderPassword => '文件夹密码';

  @override
  String get filePassword => '文件密码';

  @override
  String get enablePassword => '启用访问密码';

  @override
  String get folderInfoSaved => '文件夹信息已更新';

  @override
  String get itemInfoSaved => '信息已更新';

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
  String retriedDownloads(int count) {
    return '已重新加入 $count 个下载任务';
  }

  @override
  String retriedDownloadsPartial(int ok, int failed) {
    return '已重新加入 $ok 个下载任务，$failed 个重试失败';
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
  String get pwdHint12 => '2-12 位提取码';

  @override
  String get disablePasswordHint => '关闭访问密码需要开通会员';

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
  String get copyShareLink => '复制分享链接';

  @override
  String get copyDirectLink => '复制下载直链';

  @override
  String get shareLinkQr => '分享链接二维码';

  @override
  String get directLinkQr => '下载直链二维码';

  @override
  String get addFavorite => '添加收藏';

  @override
  String get newFavorite => '新增收藏';

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
  String get unfavorited => '已取消收藏';

  @override
  String get loading => '加载中…';

  @override
  String get cleaning => '清理中…';

  @override
  String get deleteRecordAndFile => '删除记录与文件';

  @override
  String get shareInfoUnavailable => '无法获取分享信息';

  @override
  String get share => '分享';

  @override
  String get openContainingFolder => '打开所在文件夹';

  @override
  String get more => '更多';

  @override
  String get add => '添加';

  @override
  String get searchCurrentFolder => '搜索当前目录';

  @override
  String get searchFavorites => '搜索收藏';

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
  String get properties => '属性';

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
  String get emptyFolder => '文件夹为空';

  @override
  String get reachedEnd => '已加载全部';

  @override
  String get searchIncomplete => '未全部加载内容，搜索结果可能不全';

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
  String get notifDone => '传输完成通知';

  @override
  String get notifDoneSubtitle => '下载或上传完成、失败时通知';

  @override
  String get notifDoneKeywords => '通知 完成 提醒 传输';

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
  String get managePermissions => '管理权限';

  @override
  String get managePermissionsSubtitle => '通知、安装应用、忽略电池优化';

  @override
  String get managePermissionsKeywords => 'permission manage 权限 管理 通知 安装 电池';

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
  String get fileInvalid => '文件已失效';

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
  String get addToQuickAccess => '添加到快速访问';

  @override
  String get removeFromQuickAccess => '从快速访问移除';

  @override
  String get moveToTop => '移到顶部';

  @override
  String get expand => '展开';

  @override
  String get collapse => '收起';

  @override
  String expandSection(String title) {
    return '展开$title';
  }

  @override
  String collapseSection(String title) {
    return '收起$title';
  }

  @override
  String get enteredMultiSelect => '进入多选';

  @override
  String get copy => '复制';

  @override
  String get continueLabel => '继续';

  @override
  String get showCookie => '显示 Cookie';

  @override
  String get showCookieSubtitle => 'Cookie 等同于账号登录凭据';

  @override
  String get cookieRiskTitle => '显示 Cookie？';

  @override
  String get cookieRiskMessage =>
      'Cookie 等同于账号登录凭据，任何拿到它的人都能直接登录并操作你的网盘。请勿截图、转发或粘贴到不可信的设备与应用中。';

  @override
  String get cookieAuthReason => '此操作需要验证身份';

  @override
  String get authVerifyTitle => '验证身份';

  @override
  String get authVerifyHint => '请使用指纹或锁屏密码';

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
  String get categoryPrivacy => '隐私';

  @override
  String get showCookieKeywords => 'cookie 显示 隐私 凭据 key';

  @override
  String get exportLogs => '导出近期运行日志';

  @override
  String get exportLogsSubtitle => '请在反馈问题时附带日志';

  @override
  String get exportLogsKeywords => '日志 log 反馈 排错 导出';

  @override
  String get exportLogsEmpty => '暂时没有可导出的日志';

  @override
  String get exportLogsFailed => '日志导出失败';

  @override
  String exportLogsSaved(String path) {
    return '已保存到 $path';
  }

  @override
  String get scan => '识别二维码方式';

  @override
  String get scanButton => '识别二维码';

  @override
  String get scanTakePhoto => '拍照获取';

  @override
  String get scanTakePhotoSubtitle => '用系统相机拍摄二维码图片';

  @override
  String get scanFromGallery => '从系统选取';

  @override
  String get scanFromGallerySubtitle => '从系统选择二维码图片';

  @override
  String get scanDecoding => '识别中…';

  @override
  String get scanNoCameraApp => '没有找到可用的相机应用';

  @override
  String get scanNoQrFound => '未在图片中识别到二维码';

  @override
  String get scanImageFailed => '图片识别失败';

  @override
  String get scanNotLanzou => '没有识别到蓝奏云分享链接';

  @override
  String get dynamicColor => '动态取色';

  @override
  String get dynamicColorSubtitle => '跟随系统壁纸取色';

  @override
  String get dynamicColorUnsupported => '当前系统不支持动态取色';

  @override
  String get dynamicColorKeywords => 'dynamic color monet 动态 取色 壁纸 主题';

  @override
  String get clipboardLinkPrompt => '识别剪贴板链接';

  @override
  String get clipboardLinkPromptSubtitle => '复制蓝奏云分享链接后提示打开';

  @override
  String get clipboardLinkPromptKeywords => 'clipboard 剪贴板 复制 链接 提示';

  @override
  String get clipboardLinkFound => '检测到蓝奏云分享链接';

  @override
  String get manageDefaultLinks => '管理应用默认链接';

  @override
  String get manageDefaultLinksSubtitle => '使用此应用打开分享链接';

  @override
  String get manageDefaultLinksKeywords => 'default links 默认 链接 打开方式 权限';

  @override
  String get deleteFilesToo => '同时删除文件';

  @override
  String get login => '登录';

  @override
  String get startUsingTitle => '开始使用';

  @override
  String get startUsingSubtitle => '登录账号，或从已有备份恢复应用数据。';

  @override
  String get agreementConsentPrefix => '我已阅读并同意';

  @override
  String get agreementConjunction => '与';

  @override
  String get restoreGroupTitle => '恢复';

  @override
  String get restoreExistingBackup => '从已有备份恢复';

  @override
  String get restoreIntro => '请选择备份来源';

  @override
  String get restoreLocalSource => '本地备份文件';

  @override
  String get restoreLocalSourceSubtitle => '选择之前导出的 JSON 文件';

  @override
  String get restoreCloudSource => 'WebDAV 云端';

  @override
  String get restoreCloudSourceSubtitle => '连接服务器并选择备份副本';

  @override
  String get restoreFileInvalid => '备份文件无法读取或不是有效的 UTF-8 JSON 文件';

  @override
  String get restorePreviewTitle => '确认备份内容';

  @override
  String get restoreCreatedAtLabel => '创建时间：';

  @override
  String restoreCreatedAt(String time) {
    return '创建时间：$time';
  }

  @override
  String get restoreIncludedContent => '包含内容';

  @override
  String get restoreIncludedContentLabel => '包含内容：';

  @override
  String get restoreAccountLabel => '账号：';

  @override
  String restoreAccountCount(int count) {
    return '账号：$count 个';
  }

  @override
  String restoreAccountCountValue(int count) {
    return '$count 个';
  }

  @override
  String restoreUsingAccount(String name) {
    return '恢复后使用 $name 登录';
  }

  @override
  String get restoreLoginReady => '登录状态有效，可以恢复并登录。';

  @override
  String get restoreNoLoginCookie => '此备份不含登录凭据，恢复后可继续选择登录方式。';

  @override
  String get restoreLoginInvalid => '备份中的登录状态已失效，仍可恢复其他数据。';

  @override
  String get restoreLoginNetwork => '暂时无法连接蓝奏云验证登录状态，可重试或仅恢复数据。';

  @override
  String get restoreLoginServer => '蓝奏云服务暂时异常，可重试或仅恢复数据。';

  @override
  String get restoreContainsCredentials => '此备份包含账号登录凭据，恢复时会保留本机已有登录态。';

  @override
  String get restoreNoCredentials => '此备份不含账号登录凭据，只恢复备份中的数据。';

  @override
  String get restoreCheckAgain => '重新检查';

  @override
  String get restoreAndLogin => '恢复并登录';

  @override
  String get restoreOnlyData => '仅恢复数据';

  @override
  String get restoreData => '恢复数据';

  @override
  String get restoreDataDone => '数据已恢复，请继续登录';

  @override
  String get restoreConnect => '连接并查找备份';

  @override
  String get restoreChooseCopy => '选择备份副本';

  @override
  String get webdavRestoreIntro => '请填写存放备份的 WebDAV 服务器信息';

  @override
  String get restoreInsecureTitle => '连接不安全';

  @override
  String get restoreInsecureMessage => '建议使用 HTTPS 连接，是否继续？';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get cookieLogin => 'Cookie 登录';

  @override
  String get permissionInstall => '安装应用';

  @override
  String get permissionInstallKeywords =>
      'install apk unknown sources 安装 未知来源 权限';

  @override
  String get permissionBattery => '忽略电池优化';

  @override
  String get permissionBatteryKeywords =>
      'battery optimization background 电池 优化 后台 权限';

  @override
  String get permissionChecking => '检查中…';

  @override
  String get permissionInstallGranted => '已授权（用于打开 APK）';

  @override
  String get permissionInstallDenied => '未授权（用于打开 APK）';

  @override
  String get permissionBatteryGranted => '已授权（用于后台传输）';

  @override
  String get permissionBatteryRestricted => '未授权（用于后台传输）';

  @override
  String get permissionOpenFailed => '无法打开系统设置';

  @override
  String get openSystemSettings => '前往系统管理';

  @override
  String get openSystemSettingsKeywords => '系统 设置 应用 信息 管理 app settings';

  @override
  String get backupAndRestore => '备份与恢复';

  @override
  String get backupAndRestoreSubtitle => '本地备份与 WebDAV 云端';

  @override
  String get backupKeywords => 'backup restore webdav cookie 备份 恢复 云端 导出';

  @override
  String get localBackup => '本地备份';

  @override
  String get backupNow => '立即备份';

  @override
  String get backupNowSubtitle => '导出为备份文件';

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
  String get backupContent => '备份内容';

  @override
  String get backupOptions => '备份选项';

  @override
  String get backupPageTitle => '备份';

  @override
  String get generatingBackup => '正在生成备份';

  @override
  String get backupSectionSettings => '设置项';

  @override
  String get backupSectionFavorites => '收藏夹';

  @override
  String get backupSectionQuick => '快速访问';

  @override
  String get backupSectionQuickHint => '各账号的快速访问数据';

  @override
  String get backupSectionRecents => '最近使用';

  @override
  String get backupSectionRecentsHint => '各账号的最近使用数据';

  @override
  String get backupSectionCookies => '账号列表与 Cookie';

  @override
  String get backupSectionCookiesHint => '敏感信息，等同于账号登录凭据';

  @override
  String get backupSectionWebdavHint => '敏感信息，等同于 WebDAV 登录凭据';

  @override
  String get backupSectionEmpty => '未选择';

  @override
  String get backupProtectionTitle => '保护备份';

  @override
  String get backupProtectionIntro => '使用独立密码加密备份';

  @override
  String get backupUseEncryption => '加密备份';

  @override
  String get backupPassphraseReminder => '请牢记密码，否则无法恢复数据';

  @override
  String get backupPassphrase => '备份密码';

  @override
  String get backupPassphraseHint => '至少 8 个字符';

  @override
  String get backupPassphraseRequired => '请输入备份密码';

  @override
  String get backupPassphraseTooShort => '备份密码至少需要 8 个字符';

  @override
  String get backupPassphraseMismatch => '两次输入的备份密码不一致';

  @override
  String get backupEncryptionRequired => '备份包含敏感信息，为确保数据安全需要加密备份';

  @override
  String get backupEncryptionOff => '未加密备份，请注意数据安全';

  @override
  String get backupUnlockTitle => '解锁加密备份';

  @override
  String get backupUnlockMessage => '请输入创建此备份时设置的备份密码。';

  @override
  String get backupUnlockAction => '解锁';

  @override
  String get backupPassphraseWrong => '备份密码错误或备份已损坏';

  @override
  String get restoreSensitiveAuthReason => '验证身份以使用备份中的登录凭据';

  @override
  String get webdavSection => 'WebDAV';

  @override
  String get webdavAccount => 'WebDAV 账号';

  @override
  String get webdavServer => 'WebDAV 地址';

  @override
  String get webdavServerHint => 'https://example.com/dav/';

  @override
  String get webdavUrlFormatError => 'WebDAV 地址格式错误';

  @override
  String get pleaseEnterWebdavServer => '请输入 WebDAV 地址';

  @override
  String get webdavUsername => '用户名';

  @override
  String get webdavPassword => '密码';

  @override
  String get webdavBackupPassphrase => '备份密码';

  @override
  String get webdavBackupPassphraseHint => '用于加密云端备份；修改后仅影响新备份';

  @override
  String get webdavPath => '路径';

  @override
  String get webdavPathHint => '服务器地址下的备份目录';

  @override
  String get pleaseEnterUsername => '请输入用户名';

  @override
  String get pleaseEnterPassword => '请输入密码';

  @override
  String get pleaseEnterWebdavPath => '请输入路径';

  @override
  String get webdavNotSet => '未设置';

  @override
  String get webdavNotConfigured => '未配置 WebDAV';

  @override
  String get webdavBackupContentNotSelected => '未选择备份内容';

  @override
  String get webdavAccountIncomplete => 'WebDAV 账号配置不完整，请重新填写';

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
  String get selectRestoreVersion => '选择恢复版本';

  @override
  String get restoreLatestTag => '最新版本';

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
  String get secureStorageResetTitle => '需要重新登录';

  @override
  String get secureStorageResetMessage =>
      '安全存储已升级，旧版的账号和 WebDAV 密码无法迁移。收藏、设置和本地文件仍会保留，请重新登录并重新填写 WebDAV 密码。';

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
  String get restoreConfirmMessage => '将用备份里的内容覆盖本机对应数据；备份里没有的部分保持不动，账号登录态会保留。';

  @override
  String get restoreKeepFavorites => '保留原收藏夹内容';

  @override
  String get restoreKeepFavoritesHint => '取消勾选将丢失原收藏夹数据';

  @override
  String get restoreDone => '已从备份恢复';

  @override
  String dropFilesCount(int count) {
    return '收到 $count 个文件';
  }

  @override
  String dropLinksCount(int count) {
    return '收到 $count 个链接';
  }

  @override
  String dropUploadConfirm(String path) {
    return '是否上传到当前目录（$path）？';
  }

  @override
  String get dropPickAnotherFolder => '更换目录';

  @override
  String get dropAddFavorites => '添加收藏';

  @override
  String get dropAddFavoritesHint => '解析成功后直接加入收藏';

  @override
  String get dropOpenLinks => '打开';

  @override
  String get dropOpenLinksHint => '是否逐个打开这些链接？';

  @override
  String get dropBatchFavorite => '批量收藏';

  @override
  String get dropMixedTitle => '当前拖拽内容包含多种类型，需分开处理';

  @override
  String get dropContinue => '继续';

  @override
  String dropHoverUpload(String path) {
    return '松开后上传所选文件到该目录';
  }

  @override
  String get dropHoverPickFolder => '松开后上传所选文件';

  @override
  String get dropHoverFavorite => '松开后收藏所选链接';

  @override
  String get dropHoverOpenLink => '松开后打开所选链接';

  @override
  String get dropHoverMixed => '松开后处理所选内容';

  @override
  String dropUploaded(int count) {
    return '已上传 $count 个文件';
  }

  @override
  String dropFavorited(int count) {
    return '已收藏 $count 条';
  }

  @override
  String dropNeedsPassword(int count) {
    return '$count 条需要提取码';
  }

  @override
  String dropDuplicated(int count) {
    return '$count 条已在收藏中';
  }

  @override
  String dropFailed(int count) {
    return '$count 条处理失败';
  }

  @override
  String aboutVersion(String version, int build) {
    return '$version ($build)';
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
  String get aboutSubmitIssue => '提交 Issue';

  @override
  String get relatedInfo => '相关信息';

  @override
  String get aboutBuildInfo => '构建信息';

  @override
  String get details => '详情';

  @override
  String get buildTime => '构建时间';

  @override
  String get commitHash => '提交';

  @override
  String get update => '更新';

  @override
  String get updateNotChecked => '未检测更新';

  @override
  String get updateCheckingTitle => '正在检测更新…';

  @override
  String get updateUpToDateTitle => '已是最新版本';

  @override
  String get updateFoundTitle => '检测到新版本';

  @override
  String get updateFailed => '检测更新失败';

  @override
  String get updateUnsupported => '当前平台不支持检测更新';

  @override
  String updateLastCheckAt(String time) {
    return '上次检测于 $time';
  }

  @override
  String updateReachFailed(String code) {
    return '无法连接至 GitHub ($code)';
  }

  @override
  String get updateCheck => '检测更新';

  @override
  String get updateCheckingShort => '检测中';

  @override
  String get updateRecheck => '重新检测';

  @override
  String get updateAction => '更新';

  @override
  String get updateVersionInfo => '版本信息';

  @override
  String get updateChangelog => '更新日志';

  @override
  String get updateChannel => '更新通道';

  @override
  String get updateChannelStable => '正式版';

  @override
  String get updateChannelBeta => '测试版';

  @override
  String get updateAutoCheck => '自动检查更新';

  @override
  String updateDialogTitle(String version) {
    return '检测到新版本 $version';
  }

  @override
  String get updateViewDetails => '查看详情';

  @override
  String get updateDetectedSubtitle => '检测到更新';

  @override
  String get timeJustNow => '刚刚';

  @override
  String get dayToday => '今天';

  @override
  String get dayYesterday => '昨天';

  @override
  String timeMinutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String timeTodayAt(String time) {
    return '今天 $time';
  }

  @override
  String timeYesterdayAt(String time) {
    return '昨天 $time';
  }

  @override
  String timeMonthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String timeYearMonthDay(int year, int month, int day) {
    return '$year年$month月$day日';
  }

  @override
  String get firstRunWelcome => '欢迎使用蓝云';

  @override
  String get firstRunMessage => '使用前请先阅读并同意《用户协议》与《隐私政策》。';

  @override
  String get agreeAndContinue => '下一步';

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
  String get categoryAccessibility => '无障碍';

  @override
  String get globalAnimations => '全局动画';

  @override
  String get motionModeAuto => '自动';

  @override
  String get motionModeAutoSubtitle => '启用无障碍功能后自动禁用动画';

  @override
  String get motionModeEnabled => '启用';

  @override
  String get motionModeDisabled => '禁用';

  @override
  String get motionModeKeywords => '动画 动效 全局 无障碍 移除动画 motion animation reduce';

  @override
  String get a11yFeedback => '无障碍相关问题';

  @override
  String get a11yFeedbackKeywords =>
      '无障碍 读屏 反馈 问题 邮件 邮箱 accessibility feedback email';

  @override
  String get a11yFeedbackDialogTitle => '反馈无障碍相关问题';

  @override
  String get a11yFeedbackDialogBody =>
      '如遇到无障碍相关问题，但不便在 GitHub 上反馈，可在此处通过电子邮件反馈。';

  @override
  String get feedback => '反馈';

  @override
  String get emailCopied => '已复制电子邮箱地址';

  @override
  String get termsBody =>
      '1. 本应用是蓝奏云的非官方第三方客户端，仅供个人学习与自用，与蓝奏云官方无任何关联，也未获得官方授权或认可。\n\n2. 使用本应用需要你自己的蓝奏云账号。请勿利用本应用从事违反蓝奏云服务条款、相关法律法规或侵犯他人权益的行为。\n\n3. 本应用按「现状」提供，不提供任何形式的担保。因使用本应用造成的账号受限、数据丢失、上传或下载失败等风险，由使用者自行承担。\n\n4. 应用内使用的接口来自公开渠道与非官方整理，可能随时失效；开发者不保证功能持续可用。\n\n5. 本应用以 Apache License 2.0 开源，你可以自行修改与分发代码，但请保留原始许可与版权声明，并自行承担由此产生的责任。\n\n6. 继续使用即表示你已阅读并同意本协议；如不同意，请卸载本应用。';

  @override
  String get privacyBody =>
      '1. 本应用不收集、不上传任何个人信息，没有账号系统，也没有统计、广告或崩溃上报 SDK。\n\n2. 你的蓝奏云账号（Cookie）、昵称、收藏、最近使用、传输记录与设置只保存在本机。Cookie 保存在系统加密存储中；查看 Cookie 需要先通过生物识别或锁屏验证。应用还会在本机保存运行日志（含错误信息与版本信息），只有你主动点击「导出运行日志」时才会通过系统「保存文件」对话框写入你选择的位置。\n\n3. 应用运行时直接与蓝奏云官方接口通信（pc.woozooo.com、up.woozooo.com 等），请求内容仅用于完成你发起的登录、列表、上传、下载等操作。\n\n4. 分享由系统分享面板完成：只有你主动点击分享时，选中的内容或文件才会交给你选择的应用；剪贴板仅在你主动点击「复制」时写入；「识别剪贴板链接」默认关闭，开启后（设置-通知）回到应用前台时会读取剪贴板里是否有蓝奏云分享链接，仅用于提示打开，不会上传。\n\n5. 如果你在「备份与恢复」中配置了 WebDAV，备份文件会上传到你自己填写的服务器。包含 Cookie 或 WebDAV 密码的备份必须使用独立备份密码整包加密；普通备份也可以选择加密。是否开启与上传到哪台服务器完全由你决定。\n\n6. 相机权限仅用于扫码，安装应用权限仅用于打开你下载的 APK，忽略电池优化仅用于让后台传输更稳定；这些权限都可以随时在系统设置中撤销。\n\n7. 卸载应用会一并删除本机保存的账号与数据，删除前请自行备份。';
}
