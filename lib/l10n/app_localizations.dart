import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @copiedToClipboard.
  ///
  /// In zh, this message translates to:
  /// **'已复制到剪贴板'**
  String get copiedToClipboard;

  /// No description provided for @resolvingDownload.
  ///
  /// In zh, this message translates to:
  /// **'正在解析下载地址…'**
  String get resolvingDownload;

  /// No description provided for @addedToQueue.
  ///
  /// In zh, this message translates to:
  /// **'已加入下载队列'**
  String get addedToQueue;

  /// No description provided for @shareNeedsPassword.
  ///
  /// In zh, this message translates to:
  /// **'该文件需要提取码'**
  String get shareNeedsPassword;

  /// No description provided for @resolveFailed.
  ///
  /// In zh, this message translates to:
  /// **'解析失败：{error}'**
  String resolveFailed(String error);

  /// No description provided for @tabHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get tabHome;

  /// No description provided for @tabDrive.
  ///
  /// In zh, this message translates to:
  /// **'网盘'**
  String get tabDrive;

  /// No description provided for @tabTransfers.
  ///
  /// In zh, this message translates to:
  /// **'传输'**
  String get tabTransfers;

  /// No description provided for @tabProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabProfile;

  /// No description provided for @exitTitle.
  ///
  /// In zh, this message translates to:
  /// **'还有任务在进行'**
  String get exitTitle;

  /// No description provided for @exitMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前有 {count} 个传输任务，退出会终止它们，确定退出吗？'**
  String exitMessage(int count);

  /// No description provided for @keepTransferring.
  ///
  /// In zh, this message translates to:
  /// **'继续传输'**
  String get keepTransferring;

  /// No description provided for @exitAndCancel.
  ///
  /// In zh, this message translates to:
  /// **'终止并退出'**
  String get exitAndCancel;

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @copyLink.
  ///
  /// In zh, this message translates to:
  /// **'复制链接'**
  String get copyLink;

  /// No description provided for @linkWithPassword.
  ///
  /// In zh, this message translates to:
  /// **'{url} 提取码：{pwd}'**
  String linkWithPassword(String url, String pwd);

  /// No description provided for @notLoggedIn.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get notLoggedIn;

  /// No description provided for @accountUid.
  ///
  /// In zh, this message translates to:
  /// **'账号 {uid}'**
  String accountUid(String uid);

  /// No description provided for @openShareLink.
  ///
  /// In zh, this message translates to:
  /// **'打开分享链接'**
  String get openShareLink;

  /// No description provided for @scanComingSoonTooltip.
  ///
  /// In zh, this message translates to:
  /// **'扫码（后续版本）'**
  String get scanComingSoonTooltip;

  /// No description provided for @scanComingSoon.
  ///
  /// In zh, this message translates to:
  /// **'扫码功能将在后续版本加入'**
  String get scanComingSoon;

  /// No description provided for @transferringCount.
  ///
  /// In zh, this message translates to:
  /// **'传输中 {count}'**
  String transferringCount(int count);

  /// No description provided for @transferCenter.
  ///
  /// In zh, this message translates to:
  /// **'传输中心'**
  String get transferCenter;

  /// No description provided for @quickAccess.
  ///
  /// In zh, this message translates to:
  /// **'快速访问'**
  String get quickAccess;

  /// No description provided for @quickAccessHint.
  ///
  /// In zh, this message translates to:
  /// **'可在此固定常用网盘目录'**
  String get quickAccessHint;

  /// No description provided for @recent.
  ///
  /// In zh, this message translates to:
  /// **'最近使用'**
  String get recent;

  /// No description provided for @noRecent.
  ///
  /// In zh, this message translates to:
  /// **'还没有最近使用的记录'**
  String get noRecent;

  /// No description provided for @sharedContent.
  ///
  /// In zh, this message translates to:
  /// **'分享内容'**
  String get sharedContent;

  /// No description provided for @myDrive.
  ///
  /// In zh, this message translates to:
  /// **'我的网盘'**
  String get myDrive;

  /// No description provided for @myFavorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get myFavorites;

  /// No description provided for @favoritesHint.
  ///
  /// In zh, this message translates to:
  /// **'收藏的文件和分享会出现在这里'**
  String get favoritesHint;

  /// No description provided for @favoriteFolders.
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get favoriteFolders;

  /// No description provided for @favoriteFiles.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get favoriteFiles;

  /// No description provided for @favoriteDeleteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除收藏'**
  String get favoriteDeleteConfirmTitle;

  /// No description provided for @favoriteDeleteConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'将移除选中的 {count} 个收藏，继续吗？'**
  String favoriteDeleteConfirmMessage(int count);

  /// No description provided for @unfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get unfavorite;

  /// No description provided for @addAccount.
  ///
  /// In zh, this message translates to:
  /// **'添加账号'**
  String get addAccount;

  /// No description provided for @lanCloudSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'蓝奏云第三方客户端'**
  String get lanCloudSubtitle;

  /// No description provided for @howToGetCookie.
  ///
  /// In zh, this message translates to:
  /// **'如何获取 Cookie'**
  String get howToGetCookie;

  /// No description provided for @cookieSteps.
  ///
  /// In zh, this message translates to:
  /// **'1. 用浏览器打开并登录蓝奏云官网\n2. 按 F12 打开开发者工具，切到 Network（网络）面板\n3. 随便点击一个请求，找到 Request Headers 里的 Cookie\n4. 复制整段内容（需包含 ylogin 和 phpdisk_info）'**
  String get cookieSteps;

  /// No description provided for @webLoginRecommended.
  ///
  /// In zh, this message translates to:
  /// **'网页登录（推荐）'**
  String get webLoginRecommended;

  /// No description provided for @orPasteCookie.
  ///
  /// In zh, this message translates to:
  /// **'或者手动粘贴 Cookie'**
  String get orPasteCookie;

  /// No description provided for @lanzouCookie.
  ///
  /// In zh, this message translates to:
  /// **'蓝奏云 Cookie'**
  String get lanzouCookie;

  /// No description provided for @cookieHint.
  ///
  /// In zh, this message translates to:
  /// **'ylogin=1234567; phpdisk_info=xxxxxx...'**
  String get cookieHint;

  /// No description provided for @verifying.
  ///
  /// In zh, this message translates to:
  /// **'正在验证…'**
  String get verifying;

  /// No description provided for @saveAndLogin.
  ///
  /// In zh, this message translates to:
  /// **'保存并登录'**
  String get saveAndLogin;

  /// No description provided for @cookiePrivacy.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 只保存在你手机本地（系统加密存储），不会上传到任何第三方服务器。'**
  String get cookiePrivacy;

  /// No description provided for @pleasePasteCookie.
  ///
  /// In zh, this message translates to:
  /// **'请先粘贴 Cookie'**
  String get pleasePasteCookie;

  /// No description provided for @cookieMissingYlogin.
  ///
  /// In zh, this message translates to:
  /// **'未找到 ylogin，请确认复制的是完整 Cookie'**
  String get cookieMissingYlogin;

  /// No description provided for @cookieInvalid.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 无效或已过期，请重新获取'**
  String get cookieInvalid;

  /// No description provided for @webLogin.
  ///
  /// In zh, this message translates to:
  /// **'网页登录'**
  String get webLogin;

  /// No description provided for @checking.
  ///
  /// In zh, this message translates to:
  /// **'检测中…'**
  String get checking;

  /// No description provided for @finishLogin.
  ///
  /// In zh, this message translates to:
  /// **'完成登录'**
  String get finishLogin;

  /// No description provided for @webLoginGuide.
  ///
  /// In zh, this message translates to:
  /// **'请使用你的蓝奏云账号登录；遇到滑块验证正常完成即可。登录成功跳到网盘页面后会自动保存账号。'**
  String get webLoginGuide;

  /// No description provided for @noLoginDetected.
  ///
  /// In zh, this message translates to:
  /// **'还没有检测到登录状态，请先在上方页面完成登录'**
  String get noLoginDetected;

  /// No description provided for @my.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get my;

  /// No description provided for @uidLabel.
  ///
  /// In zh, this message translates to:
  /// **'UID: {uid}'**
  String uidLabel(String uid);

  /// No description provided for @switchAccountShort.
  ///
  /// In zh, this message translates to:
  /// **'切换'**
  String get switchAccountShort;

  /// No description provided for @switchAccount.
  ///
  /// In zh, this message translates to:
  /// **'切换账号'**
  String get switchAccount;

  /// No description provided for @removeCurrentAccount.
  ///
  /// In zh, this message translates to:
  /// **'移除当前账号'**
  String get removeCurrentAccount;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @settingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'外观、行为、连接与高级覆盖项'**
  String get settingsSubtitle;

  /// No description provided for @webManagement.
  ///
  /// In zh, this message translates to:
  /// **'网页版'**
  String get webManagement;

  /// No description provided for @webManagementSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'修改密码、头像等官方功能'**
  String get webManagementSubtitle;

  /// No description provided for @recycleBin.
  ///
  /// In zh, this message translates to:
  /// **'回收站'**
  String get recycleBin;

  /// No description provided for @removeAccountTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除账号'**
  String get removeAccountTitle;

  /// No description provided for @removeAccountMessage.
  ///
  /// In zh, this message translates to:
  /// **'将从本机移除账号 {uid} 及其登录信息，云端文件不受影响。'**
  String removeAccountMessage(String uid);

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @transfers.
  ///
  /// In zh, this message translates to:
  /// **'传输'**
  String get transfers;

  /// No description provided for @clearFinished.
  ///
  /// In zh, this message translates to:
  /// **'清除已完成'**
  String get clearFinished;

  /// No description provided for @upload.
  ///
  /// In zh, this message translates to:
  /// **'上传'**
  String get upload;

  /// No description provided for @noUploads.
  ///
  /// In zh, this message translates to:
  /// **'暂无上传任务'**
  String get noUploads;

  /// No description provided for @noDownloads.
  ///
  /// In zh, this message translates to:
  /// **'暂无下载任务'**
  String get noDownloads;

  /// No description provided for @inProgress.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get inProgress;

  /// No description provided for @finished.
  ///
  /// In zh, this message translates to:
  /// **'已结束'**
  String get finished;

  /// No description provided for @queued.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get queued;

  /// No description provided for @uploading.
  ///
  /// In zh, this message translates to:
  /// **'上传中'**
  String get uploading;

  /// No description provided for @downloading.
  ///
  /// In zh, this message translates to:
  /// **'下载中'**
  String get downloading;

  /// No description provided for @completed.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get completed;

  /// No description provided for @failedWithError.
  ///
  /// In zh, this message translates to:
  /// **'失败：{error}'**
  String failedWithError(String error);

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get unknownError;

  /// No description provided for @canceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get canceled;

  /// No description provided for @unknownSize.
  ///
  /// In zh, this message translates to:
  /// **'未知大小'**
  String get unknownSize;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @open.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get open;

  /// No description provided for @pleasePasteShareLink.
  ///
  /// In zh, this message translates to:
  /// **'请先粘贴蓝奏云分享链接'**
  String get pleasePasteShareLink;

  /// No description provided for @addedToFavorites.
  ///
  /// In zh, this message translates to:
  /// **'已加入收藏'**
  String get addedToFavorites;

  /// No description provided for @openShare.
  ///
  /// In zh, this message translates to:
  /// **'打开链接'**
  String get openShare;

  /// No description provided for @shareLink.
  ///
  /// In zh, this message translates to:
  /// **'分享链接'**
  String get shareLink;

  /// No description provided for @shareLinkHint.
  ///
  /// In zh, this message translates to:
  /// **'https://www.lanzou.com/xxxxx'**
  String get shareLinkHint;

  /// No description provided for @passwordOptional.
  ///
  /// In zh, this message translates to:
  /// **'提取码（如有）'**
  String get passwordOptional;

  /// No description provided for @resolving.
  ///
  /// In zh, this message translates to:
  /// **'解析中…'**
  String get resolving;

  /// No description provided for @resolve.
  ///
  /// In zh, this message translates to:
  /// **'解析'**
  String get resolve;

  /// No description provided for @sizeLabel.
  ///
  /// In zh, this message translates to:
  /// **'大小：{size}'**
  String sizeLabel(String size);

  /// No description provided for @favorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favorite;

  /// No description provided for @shareEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个分享里没有文件'**
  String get shareEmpty;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @chinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get chinese;

  /// No description provided for @english.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @themeMode.
  ///
  /// In zh, this message translates to:
  /// **'深浅色模式'**
  String get themeMode;

  /// No description provided for @light.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get dark;

  /// No description provided for @themeModeKeywords.
  ///
  /// In zh, this message translates to:
  /// **'主题 夜间 深色 浅色'**
  String get themeModeKeywords;

  /// No description provided for @oled.
  ///
  /// In zh, this message translates to:
  /// **'纯黑主题'**
  String get oled;

  /// No description provided for @oledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'深色模式下用纯黑背景，更省电'**
  String get oledSubtitle;

  /// No description provided for @oledKeywords.
  ///
  /// In zh, this message translates to:
  /// **'纯黑 省电 oled'**
  String get oledKeywords;

  /// No description provided for @themeColor.
  ///
  /// In zh, this message translates to:
  /// **'主题色'**
  String get themeColor;

  /// No description provided for @themeColorKeywords.
  ///
  /// In zh, this message translates to:
  /// **'配色 颜色 主题'**
  String get themeColorKeywords;

  /// No description provided for @classicBlue.
  ///
  /// In zh, this message translates to:
  /// **'经典蓝'**
  String get classicBlue;

  /// No description provided for @teal.
  ///
  /// In zh, this message translates to:
  /// **'青绿'**
  String get teal;

  /// No description provided for @violet.
  ///
  /// In zh, this message translates to:
  /// **'紫罗兰'**
  String get violet;

  /// No description provided for @vermilion.
  ///
  /// In zh, this message translates to:
  /// **'朱红'**
  String get vermilion;

  /// No description provided for @olive.
  ///
  /// In zh, this message translates to:
  /// **'橄榄绿'**
  String get olive;

  /// No description provided for @custom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get custom;

  /// No description provided for @hideTopBar.
  ///
  /// In zh, this message translates to:
  /// **'顶栏收起'**
  String get hideTopBar;

  /// No description provided for @hideTopBarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'列表滑动时收起顶栏'**
  String get hideTopBarSubtitle;

  /// No description provided for @hideTopBarKeywords.
  ///
  /// In zh, this message translates to:
  /// **'顶栏 滑动隐藏 收起'**
  String get hideTopBarKeywords;

  /// No description provided for @hideBottomBar.
  ///
  /// In zh, this message translates to:
  /// **'底栏收起'**
  String get hideBottomBar;

  /// No description provided for @hideBottomBarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'列表滑动时收起底栏'**
  String get hideBottomBarSubtitle;

  /// No description provided for @hideBottomBarKeywords.
  ///
  /// In zh, this message translates to:
  /// **'底栏 滑动隐藏 收起'**
  String get hideBottomBarKeywords;

  /// No description provided for @floatingNav.
  ///
  /// In zh, this message translates to:
  /// **'悬浮底栏'**
  String get floatingNav;

  /// No description provided for @floatingNavSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'带圆角和阴影，浮在内容之上'**
  String get floatingNavSubtitle;

  /// No description provided for @floatingNavKeywords.
  ///
  /// In zh, this message translates to:
  /// **'底栏 悬浮 md3'**
  String get floatingNavKeywords;

  /// No description provided for @swipeTabs.
  ///
  /// In zh, this message translates to:
  /// **'横滑切换视图'**
  String get swipeTabs;

  /// No description provided for @swipeTabsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'左右滑动在首页/网盘/传输/我的之间切换'**
  String get swipeTabsSubtitle;

  /// No description provided for @swipeTabsKeywords.
  ///
  /// In zh, this message translates to:
  /// **'滑动 手势 tab'**
  String get swipeTabsKeywords;

  /// No description provided for @transitionAnimations.
  ///
  /// In zh, this message translates to:
  /// **'过渡动画'**
  String get transitionAnimations;

  /// No description provided for @transitionAnimationsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'目录切换与列表出现时的淡入动画'**
  String get transitionAnimationsSubtitle;

  /// No description provided for @transitionAnimationsKeywords.
  ///
  /// In zh, this message translates to:
  /// **'动画 过渡 淡入 目录 列表'**
  String get transitionAnimationsKeywords;

  /// No description provided for @downloadDir.
  ///
  /// In zh, this message translates to:
  /// **'下载目录'**
  String get downloadDir;

  /// No description provided for @defaultDownloadDir.
  ///
  /// In zh, this message translates to:
  /// **'默认（应用文档目录/LanCloud）'**
  String get defaultDownloadDir;

  /// No description provided for @downloadDirKeywords.
  ///
  /// In zh, this message translates to:
  /// **'下载 目录 保存位置'**
  String get downloadDirKeywords;

  /// No description provided for @launchPage.
  ///
  /// In zh, this message translates to:
  /// **'默认启动页'**
  String get launchPage;

  /// No description provided for @launchPageKeywords.
  ///
  /// In zh, this message translates to:
  /// **'启动 首页 网盘'**
  String get launchPageKeywords;

  /// No description provided for @homeFolderOpen.
  ///
  /// In zh, this message translates to:
  /// **'首页目录打开方式'**
  String get homeFolderOpen;

  /// No description provided for @homeFolderOpenKeywords.
  ///
  /// In zh, this message translates to:
  /// **'首页 目录 打开方式 新页面 网盘'**
  String get homeFolderOpenKeywords;

  /// No description provided for @openInNewPage.
  ///
  /// In zh, this message translates to:
  /// **'新页面'**
  String get openInNewPage;

  /// No description provided for @openInDriveTab.
  ///
  /// In zh, this message translates to:
  /// **'网盘页'**
  String get openInDriveTab;

  /// No description provided for @cacheFolders.
  ///
  /// In zh, this message translates to:
  /// **'缓存目录数据'**
  String get cacheFolders;

  /// No description provided for @cacheFoldersSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'返回上一级时不再重新加载'**
  String get cacheFoldersSubtitle;

  /// No description provided for @cacheFoldersKeywords.
  ///
  /// In zh, this message translates to:
  /// **'缓存 目录'**
  String get cacheFoldersKeywords;

  /// No description provided for @loadAllPages.
  ///
  /// In zh, this message translates to:
  /// **'自动加载全部目录内容'**
  String get loadAllPages;

  /// No description provided for @loadAllPagesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭时按页加载，滑到底部再加载下一页'**
  String get loadAllPagesSubtitle;

  /// No description provided for @loadAllPagesKeywords.
  ///
  /// In zh, this message translates to:
  /// **'分页 加载 目录'**
  String get loadAllPagesKeywords;

  /// No description provided for @requestInterval.
  ///
  /// In zh, this message translates to:
  /// **'网络请求间隔'**
  String get requestInterval;

  /// No description provided for @requestIntervalSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{ms} ms'**
  String requestIntervalSubtitle(int ms);

  /// No description provided for @requestIntervalHint.
  ///
  /// In zh, this message translates to:
  /// **'默认 100 ms；间隔过小可能触发服务端限流，请谨慎调整。'**
  String get requestIntervalHint;

  /// No description provided for @requestIntervalKeywords.
  ///
  /// In zh, this message translates to:
  /// **'间隔 限流 风控 请求'**
  String get requestIntervalKeywords;

  /// No description provided for @maxUploads.
  ///
  /// In zh, this message translates to:
  /// **'同时上传数量'**
  String get maxUploads;

  /// No description provided for @uploadKeywords.
  ///
  /// In zh, this message translates to:
  /// **'上传 并发'**
  String get uploadKeywords;

  /// No description provided for @maxDownloads.
  ///
  /// In zh, this message translates to:
  /// **'同时下载数量'**
  String get maxDownloads;

  /// No description provided for @downloadKeywords.
  ///
  /// In zh, this message translates to:
  /// **'下载 并发'**
  String get downloadKeywords;

  /// No description provided for @apiHost.
  ///
  /// In zh, this message translates to:
  /// **'网盘接口域名'**
  String get apiHost;

  /// No description provided for @apiHostKeywords.
  ///
  /// In zh, this message translates to:
  /// **'域名 接口 连接异常 pc up'**
  String get apiHostKeywords;

  /// No description provided for @uploadDomain.
  ///
  /// In zh, this message translates to:
  /// **'上传域名'**
  String get uploadDomain;

  /// No description provided for @defaultUploadDomain.
  ///
  /// In zh, this message translates to:
  /// **'默认（up.woozooo.com）'**
  String get defaultUploadDomain;

  /// No description provided for @uploadDomainKeywords.
  ///
  /// In zh, this message translates to:
  /// **'上传 域名 up'**
  String get uploadDomainKeywords;

  /// No description provided for @shareDomain.
  ///
  /// In zh, this message translates to:
  /// **'分享链接域名'**
  String get shareDomain;

  /// No description provided for @defaultShareDomain.
  ///
  /// In zh, this message translates to:
  /// **'默认（自动尝试内置镜像）'**
  String get defaultShareDomain;

  /// No description provided for @shareDomainKeywords.
  ///
  /// In zh, this message translates to:
  /// **'分享 域名 镜像 链接'**
  String get shareDomainKeywords;

  /// No description provided for @userAgent.
  ///
  /// In zh, this message translates to:
  /// **'自定义 User-Agent'**
  String get userAgent;

  /// No description provided for @defaultUserAgent.
  ///
  /// In zh, this message translates to:
  /// **'默认（模拟桌面浏览器）'**
  String get defaultUserAgent;

  /// No description provided for @userAgentKeywords.
  ///
  /// In zh, this message translates to:
  /// **'ua user-agent 浏览器'**
  String get userAgentKeywords;

  /// No description provided for @advanced.
  ///
  /// In zh, this message translates to:
  /// **'高级覆盖项'**
  String get advanced;

  /// No description provided for @advancedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'接口/上传/分享域名与自定义 UA'**
  String get advancedSubtitle;

  /// No description provided for @advancedHint.
  ///
  /// In zh, this message translates to:
  /// **'仅在连接异常或域名被墙时修改，留空恢复默认'**
  String get advancedHint;

  /// No description provided for @clearRecents.
  ///
  /// In zh, this message translates to:
  /// **'清空最近使用记录'**
  String get clearRecents;

  /// No description provided for @clearRecentsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'删除首页最近使用条目'**
  String get clearRecentsSubtitle;

  /// No description provided for @clearRecentsKeywords.
  ///
  /// In zh, this message translates to:
  /// **'最近 清空 记录'**
  String get clearRecentsKeywords;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @aboutSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'LanCloud · 蓝奏云第三方客户端'**
  String get aboutSubtitle;

  /// No description provided for @aboutKeywords.
  ///
  /// In zh, this message translates to:
  /// **'版本 关于 开源 协议'**
  String get aboutKeywords;

  /// No description provided for @aboutText.
  ///
  /// In zh, this message translates to:
  /// **'自用的蓝奏云第三方客户端，基于非官方接口实现，请勿传播或用于商业用途。'**
  String get aboutText;

  /// No description provided for @searchSettings.
  ///
  /// In zh, this message translates to:
  /// **'搜索设置'**
  String get searchSettings;

  /// No description provided for @closeSearch.
  ///
  /// In zh, this message translates to:
  /// **'关闭搜索'**
  String get closeSearch;

  /// No description provided for @searchPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词搜索设置，如：域名、收起、下载、并发'**
  String get searchPlaceholder;

  /// No description provided for @noMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的设置项'**
  String get noMatch;

  /// No description provided for @cleared.
  ///
  /// In zh, this message translates to:
  /// **'已清空'**
  String get cleared;

  /// No description provided for @restoredDefaultDir.
  ///
  /// In zh, this message translates to:
  /// **'已恢复默认目录'**
  String get restoredDefaultDir;

  /// No description provided for @restoreDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get restoreDefault;

  /// No description provided for @change.
  ///
  /// In zh, this message translates to:
  /// **'更改'**
  String get change;

  /// No description provided for @downloadDirSet.
  ///
  /// In zh, this message translates to:
  /// **'下载目录已设为 {dir}'**
  String downloadDirSet(String dir);

  /// No description provided for @pickDirFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择目录失败：{error}'**
  String pickDirFailed(String error);

  /// No description provided for @noInterval.
  ///
  /// In zh, this message translates to:
  /// **'不间隔'**
  String get noInterval;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @reset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get reset;

  /// No description provided for @includeWebdavAccount.
  ///
  /// In zh, this message translates to:
  /// **'备份包含 WebDAV 账号'**
  String get includeWebdavAccount;

  /// No description provided for @includeWebdavAccountSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'危险！启用后，备份文件包含 WebDAV 地址与密码，请注意信息安全'**
  String get includeWebdavAccountSubtitle;

  /// No description provided for @uploadDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'留空使用默认 up.woozooo.com，可带 https://'**
  String get uploadDomainHint;

  /// No description provided for @shareDomainHint.
  ///
  /// In zh, this message translates to:
  /// **'留空自动尝试内置镜像，可带 https://'**
  String get shareDomainHint;

  /// No description provided for @userAgentHint.
  ///
  /// In zh, this message translates to:
  /// **'留空表示使用默认值'**
  String get userAgentHint;

  /// No description provided for @categoryAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get categoryAppearance;

  /// No description provided for @categoryBehavior.
  ///
  /// In zh, this message translates to:
  /// **'行为'**
  String get categoryBehavior;

  /// No description provided for @categoryConnection.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get categoryConnection;

  /// No description provided for @categoryAdvanced.
  ///
  /// In zh, this message translates to:
  /// **'高级覆盖项'**
  String get categoryAdvanced;

  /// No description provided for @categoryData.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get categoryData;

  /// No description provided for @exitSelection.
  ///
  /// In zh, this message translates to:
  /// **'退出多选'**
  String get exitSelection;

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 项'**
  String selectedCount(int count);

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @invertSelection.
  ///
  /// In zh, this message translates to:
  /// **'反选'**
  String get invertSelection;

  /// No description provided for @newFolder.
  ///
  /// In zh, this message translates to:
  /// **'新建文件夹'**
  String get newFolder;

  /// No description provided for @uploadFile.
  ///
  /// In zh, this message translates to:
  /// **'上传文件'**
  String get uploadFile;

  /// No description provided for @uploadFileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从本机或其他应用中选择文件'**
  String get uploadFileSubtitle;

  /// No description provided for @uploadSkipped.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {added} 个上传任务，跳过 {skipped} 个超过 100MB 的文件'**
  String uploadSkipped(int added, int skipped);

  /// No description provided for @uploadAdded.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {count} 个上传任务'**
  String uploadAdded(int count);

  /// No description provided for @nameRequired.
  ///
  /// In zh, this message translates to:
  /// **'名称（必填）'**
  String get nameRequired;

  /// No description provided for @descOptional.
  ///
  /// In zh, this message translates to:
  /// **'简介（选填）'**
  String get descOptional;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @folderNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'文件夹名称不能为空'**
  String get folderNameRequired;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除确认'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'将把选中的 {count} 个条目移入回收站，继续吗？'**
  String deleteConfirmMessage(int count);

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @folderInfo.
  ///
  /// In zh, this message translates to:
  /// **'修改信息'**
  String get folderInfo;

  /// No description provided for @folderInfoSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'修改名称与简介'**
  String get folderInfoSubtitle;

  /// No description provided for @accessPassword.
  ///
  /// In zh, this message translates to:
  /// **'访问密码'**
  String get accessPassword;

  /// No description provided for @accessPasswordSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'可设置或关闭访问密码'**
  String get accessPasswordSubtitle;

  /// No description provided for @enablePassword.
  ///
  /// In zh, this message translates to:
  /// **'启用访问密码'**
  String get enablePassword;

  /// No description provided for @folderInfoSaved.
  ///
  /// In zh, this message translates to:
  /// **'文件夹信息已更新'**
  String get folderInfoSaved;

  /// No description provided for @passwordCleared.
  ///
  /// In zh, this message translates to:
  /// **'已关闭访问密码'**
  String get passwordCleared;

  /// No description provided for @passwordClearedCount.
  ///
  /// In zh, this message translates to:
  /// **'已关闭 {count} 项的访问密码'**
  String passwordClearedCount(int count);

  /// No description provided for @transferDeleteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除传输记录'**
  String get transferDeleteConfirmTitle;

  /// No description provided for @transferDeleteConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'将移除选中的 {count} 条记录（进行中的会先取消），继续吗？'**
  String transferDeleteConfirmMessage(int count);

  /// No description provided for @batchDownload.
  ///
  /// In zh, this message translates to:
  /// **'批量下载'**
  String get batchDownload;

  /// No description provided for @resolvingBatch.
  ///
  /// In zh, this message translates to:
  /// **'正在解析并加入下载队列（共 {count} 个）'**
  String resolvingBatch(int count);

  /// No description provided for @addedDownloads.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {count} 个下载任务'**
  String addedDownloads(int count);

  /// No description provided for @addedDownloadsPartial.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {ok} 个下载任务，{failed} 个解析失败'**
  String addedDownloadsPartial(int ok, int failed);

  /// No description provided for @noLinksToCopy.
  ///
  /// In zh, this message translates to:
  /// **'没有可复制的分享链接'**
  String get noLinksToCopy;

  /// No description provided for @passwordLabel.
  ///
  /// In zh, this message translates to:
  /// **'提取码：{pwd}'**
  String passwordLabel(String pwd);

  /// No description provided for @favoritedCount.
  ///
  /// In zh, this message translates to:
  /// **'已收藏 {count} 个条目'**
  String favoritedCount(int count);

  /// No description provided for @move.
  ///
  /// In zh, this message translates to:
  /// **'移动'**
  String get move;

  /// No description provided for @moveSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'把选中的文件/文件夹移动到其他目录'**
  String get moveSubtitle;

  /// No description provided for @editDesc.
  ///
  /// In zh, this message translates to:
  /// **'修改简介'**
  String get editDesc;

  /// No description provided for @editDescBatchSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'批量设置选中的文件/文件夹简介'**
  String get editDescBatchSubtitle;

  /// No description provided for @setPassword.
  ///
  /// In zh, this message translates to:
  /// **'设置访问密码'**
  String get setPassword;

  /// No description provided for @setPasswordSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'批量设置选中条目的访问密码；免费账号只能设置不能关闭'**
  String get setPasswordSubtitle;

  /// No description provided for @movedTo.
  ///
  /// In zh, this message translates to:
  /// **'已移动 {count} 个条目到「{name}」'**
  String movedTo(int count, String name);

  /// No description provided for @movedPartial.
  ///
  /// In zh, this message translates to:
  /// **'已移动 {ok} 个条目，{failed} 个失败'**
  String movedPartial(int ok, int failed);

  /// No description provided for @newDescHint.
  ///
  /// In zh, this message translates to:
  /// **'输入新的简介'**
  String get newDescHint;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @descUpdatedCount.
  ///
  /// In zh, this message translates to:
  /// **'已修改 {count} 个条目的简介'**
  String descUpdatedCount(int count);

  /// No description provided for @descUpdatedPartial.
  ///
  /// In zh, this message translates to:
  /// **'已修改 {ok} 个，{failed} 个失败'**
  String descUpdatedPartial(int ok, int failed);

  /// No description provided for @pwdHint.
  ///
  /// In zh, this message translates to:
  /// **'2-6 位提取码'**
  String get pwdHint;

  /// No description provided for @pwdTooShort.
  ///
  /// In zh, this message translates to:
  /// **'提取码至少 2 位'**
  String get pwdTooShort;

  /// No description provided for @passwordSetCount.
  ///
  /// In zh, this message translates to:
  /// **'已为 {count} 个条目设置提取码'**
  String passwordSetCount(int count);

  /// No description provided for @passwordSetPartial.
  ///
  /// In zh, this message translates to:
  /// **'已设置 {ok} 个，{failed} 个失败'**
  String passwordSetPartial(int ok, int failed);

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @downloadsCount.
  ///
  /// In zh, this message translates to:
  /// **'下载 {count}'**
  String downloadsCount(int count);

  /// No description provided for @hasPassword.
  ///
  /// In zh, this message translates to:
  /// **'有提取码'**
  String get hasPassword;

  /// No description provided for @openLink.
  ///
  /// In zh, this message translates to:
  /// **'打开链接'**
  String get openLink;

  /// No description provided for @showQr.
  ///
  /// In zh, this message translates to:
  /// **'显示二维码'**
  String get showQr;

  /// No description provided for @addFavorite.
  ///
  /// In zh, this message translates to:
  /// **'添加收藏'**
  String get addFavorite;

  /// No description provided for @moreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get moreActions;

  /// No description provided for @freeAccountPasswordNote.
  ///
  /// In zh, this message translates to:
  /// **'免费账号只能设置不能关闭'**
  String get freeAccountPasswordNote;

  /// No description provided for @descUpdated.
  ///
  /// In zh, this message translates to:
  /// **'简介已更新'**
  String get descUpdated;

  /// No description provided for @passwordSet.
  ///
  /// In zh, this message translates to:
  /// **'已设置提取码'**
  String get passwordSet;

  /// No description provided for @favorited.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get favorited;

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @add.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get add;

  /// No description provided for @searchCurrentFolder.
  ///
  /// In zh, this message translates to:
  /// **'搜索当前目录'**
  String get searchCurrentFolder;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @menu.
  ///
  /// In zh, this message translates to:
  /// **'菜单'**
  String get menu;

  /// No description provided for @layout.
  ///
  /// In zh, this message translates to:
  /// **'布局'**
  String get layout;

  /// No description provided for @grid.
  ///
  /// In zh, this message translates to:
  /// **'网格'**
  String get grid;

  /// No description provided for @list.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get list;

  /// No description provided for @sort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sort;

  /// No description provided for @sortName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get sortName;

  /// No description provided for @sortSize.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get sortSize;

  /// No description provided for @sortTime.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get sortTime;

  /// No description provided for @folderProperties.
  ///
  /// In zh, this message translates to:
  /// **'目录属性'**
  String get folderProperties;

  /// No description provided for @sortByName.
  ///
  /// In zh, this message translates to:
  /// **'按名称排序'**
  String get sortByName;

  /// No description provided for @sortBySize.
  ///
  /// In zh, this message translates to:
  /// **'按大小排序'**
  String get sortBySize;

  /// No description provided for @sortByTime.
  ///
  /// In zh, this message translates to:
  /// **'按时间排序'**
  String get sortByTime;

  /// No description provided for @toggleLayout.
  ///
  /// In zh, this message translates to:
  /// **'切换布局样式'**
  String get toggleLayout;

  /// No description provided for @multiSelect.
  ///
  /// In zh, this message translates to:
  /// **'多选'**
  String get multiSelect;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @root.
  ///
  /// In zh, this message translates to:
  /// **'根目录'**
  String get root;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{error}'**
  String loadFailed(String error);

  /// No description provided for @noMatchContent.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配「{query}」的内容'**
  String noMatchContent(String query);

  /// No description provided for @emptyFolder.
  ///
  /// In zh, this message translates to:
  /// **'这个文件夹是空的'**
  String get emptyFolder;

  /// No description provided for @reachedEnd.
  ///
  /// In zh, this message translates to:
  /// **'已经到底了'**
  String get reachedEnd;

  /// No description provided for @filterResult.
  ///
  /// In zh, this message translates to:
  /// **'筛选结果'**
  String get filterResult;

  /// No description provided for @folderActions.
  ///
  /// In zh, this message translates to:
  /// **'文件夹操作'**
  String get folderActions;

  /// No description provided for @fileActions.
  ///
  /// In zh, this message translates to:
  /// **'文件操作'**
  String get fileActions;

  /// No description provided for @downloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载'**
  String get downloaded;

  /// No description provided for @folder.
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get folder;

  /// No description provided for @fileCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件'**
  String fileCount(int count);

  /// No description provided for @openFolder.
  ///
  /// In zh, this message translates to:
  /// **'打开文件夹'**
  String get openFolder;

  /// No description provided for @chooseTargetFolder.
  ///
  /// In zh, this message translates to:
  /// **'选择目标文件夹'**
  String get chooseTargetFolder;

  /// No description provided for @parentFolder.
  ///
  /// In zh, this message translates to:
  /// **'上一级'**
  String get parentFolder;

  /// No description provided for @moveHere.
  ///
  /// In zh, this message translates to:
  /// **'移动到此'**
  String get moveHere;

  /// No description provided for @noSubfolders.
  ///
  /// In zh, this message translates to:
  /// **'这个文件夹里没有子文件夹'**
  String get noSubfolders;

  /// No description provided for @notifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get notifications;

  /// No description provided for @notifProgress.
  ///
  /// In zh, this message translates to:
  /// **'传输进度通知'**
  String get notifProgress;

  /// No description provided for @notifProgressSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'传输进行中在通知栏显示进度'**
  String get notifProgressSubtitle;

  /// No description provided for @notifProgressKeywords.
  ///
  /// In zh, this message translates to:
  /// **'通知 进度 传输'**
  String get notifProgressKeywords;

  /// No description provided for @notifDone.
  ///
  /// In zh, this message translates to:
  /// **'传输完成提醒'**
  String get notifDone;

  /// No description provided for @notifDoneSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'下载或上传完成、失败时提醒'**
  String get notifDoneSubtitle;

  /// No description provided for @notifDoneKeywords.
  ///
  /// In zh, this message translates to:
  /// **'通知 完成 提醒'**
  String get notifDoneKeywords;

  /// No description provided for @notifPermission.
  ///
  /// In zh, this message translates to:
  /// **'通知权限'**
  String get notifPermission;

  /// No description provided for @notifPermissionKeywords.
  ///
  /// In zh, this message translates to:
  /// **'通知 权限 授权'**
  String get notifPermissionKeywords;

  /// No description provided for @notifPermissionChecking.
  ///
  /// In zh, this message translates to:
  /// **'检查中…'**
  String get notifPermissionChecking;

  /// No description provided for @notifPermissionGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授权'**
  String get notifPermissionGranted;

  /// No description provided for @notifPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'未授权'**
  String get notifPermissionDenied;

  /// No description provided for @notifPermissionDeniedHint.
  ///
  /// In zh, this message translates to:
  /// **'通知权限未开启，请到系统设置中允许通知'**
  String get notifPermissionDeniedHint;

  /// No description provided for @notifProgressTitle.
  ///
  /// In zh, this message translates to:
  /// **'传输中'**
  String get notifProgressTitle;

  /// No description provided for @notifProgressBody.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个任务进行中'**
  String notifProgressBody(int count);

  /// No description provided for @notifUploadDone.
  ///
  /// In zh, this message translates to:
  /// **'上传完成'**
  String get notifUploadDone;

  /// No description provided for @notifDownloadDone.
  ///
  /// In zh, this message translates to:
  /// **'下载完成'**
  String get notifDownloadDone;

  /// No description provided for @notifFailed.
  ///
  /// In zh, this message translates to:
  /// **'传输失败'**
  String get notifFailed;

  /// No description provided for @notifChannelProgress.
  ///
  /// In zh, this message translates to:
  /// **'传输进度'**
  String get notifChannelProgress;

  /// No description provided for @notifChannelProgressDesc.
  ///
  /// In zh, this message translates to:
  /// **'下载与上传进行中的进度'**
  String get notifChannelProgressDesc;

  /// No description provided for @notifChannelDone.
  ///
  /// In zh, this message translates to:
  /// **'传输完成'**
  String get notifChannelDone;

  /// No description provided for @notifChannelDoneDesc.
  ///
  /// In zh, this message translates to:
  /// **'下载与上传完成或失败的提醒'**
  String get notifChannelDoneDesc;

  /// No description provided for @files.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get files;

  /// No description provided for @shareMessage.
  ///
  /// In zh, this message translates to:
  /// **'来自分享者的信息'**
  String get shareMessage;

  /// No description provided for @favoritedPartial.
  ///
  /// In zh, this message translates to:
  /// **'{ok} 个已收藏，{failed} 个失败'**
  String favoritedPartial(int ok, int failed);

  /// No description provided for @file.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get file;

  /// No description provided for @sharerLabel.
  ///
  /// In zh, this message translates to:
  /// **'分享者 {name}'**
  String sharerLabel(String name);

  /// No description provided for @editInfo.
  ///
  /// In zh, this message translates to:
  /// **'修改信息'**
  String get editInfo;

  /// No description provided for @favoriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义标题'**
  String get favoriteTitle;

  /// No description provided for @favoriteTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用默认名称'**
  String get favoriteTitleHint;

  /// No description provided for @shareInvalid.
  ///
  /// In zh, this message translates to:
  /// **'该分享已失效（已取消或删除）'**
  String get shareInvalid;

  /// No description provided for @manage.
  ///
  /// In zh, this message translates to:
  /// **'管理'**
  String get manage;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'蓝云'**
  String get appName;

  /// No description provided for @shareReceivedFiles.
  ///
  /// In zh, this message translates to:
  /// **'已接收 {count} 个文件，开始上传'**
  String shareReceivedFiles(int count);

  /// No description provided for @shareTargetUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'无法识别的分享内容'**
  String get shareTargetUnsupported;

  /// No description provided for @uploadHere.
  ///
  /// In zh, this message translates to:
  /// **'上传到此'**
  String get uploadHere;

  /// No description provided for @uploadFromApp.
  ///
  /// In zh, this message translates to:
  /// **'从应用上传'**
  String get uploadFromApp;

  /// No description provided for @uploadTasksAdded.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {count} 个上传任务'**
  String uploadTasksAdded(int count);

  /// No description provided for @install.
  ///
  /// In zh, this message translates to:
  /// **'安装'**
  String get install;

  /// No description provided for @notifDoneCount.
  ///
  /// In zh, this message translates to:
  /// **'已完成 {count} 个'**
  String notifDoneCount(int count);

  /// No description provided for @addToQuickAccess.
  ///
  /// In zh, this message translates to:
  /// **'添加到快速访问'**
  String get addToQuickAccess;

  /// No description provided for @removeFromQuickAccess.
  ///
  /// In zh, this message translates to:
  /// **'从快速访问移除'**
  String get removeFromQuickAccess;

  /// No description provided for @unpin.
  ///
  /// In zh, this message translates to:
  /// **'取消固定'**
  String get unpin;

  /// No description provided for @moveToTop.
  ///
  /// In zh, this message translates to:
  /// **'移到顶部'**
  String get moveToTop;

  /// No description provided for @expand.
  ///
  /// In zh, this message translates to:
  /// **'展开'**
  String get expand;

  /// No description provided for @collapse.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get collapse;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @continueLabel.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get continueLabel;

  /// No description provided for @showCookie.
  ///
  /// In zh, this message translates to:
  /// **'显示 Cookie'**
  String get showCookie;

  /// No description provided for @showCookieSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'需通过生物识别 / 锁屏验证'**
  String get showCookieSubtitle;

  /// No description provided for @cookieRiskTitle.
  ///
  /// In zh, this message translates to:
  /// **'显示 Cookie？'**
  String get cookieRiskTitle;

  /// No description provided for @cookieRiskMessage.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 等同于账号登录凭据，任何拿到它的人都能直接登录并操作你的网盘。请勿截图、转发或粘贴到不可信的设备与应用中。'**
  String get cookieRiskMessage;

  /// No description provided for @cookieAuthReason.
  ///
  /// In zh, this message translates to:
  /// **'验证身份后显示 Cookie'**
  String get cookieAuthReason;

  /// No description provided for @cookieAuthFailed.
  ///
  /// In zh, this message translates to:
  /// **'身份验证未通过，已取消显示'**
  String get cookieAuthFailed;

  /// No description provided for @cookieAuthUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前设备未设置锁屏密码或生物识别，无法验证身份'**
  String get cookieAuthUnavailable;

  /// No description provided for @cookieSheetTitle.
  ///
  /// In zh, this message translates to:
  /// **'账号 Cookie'**
  String get cookieSheetTitle;

  /// No description provided for @cookieExport.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get cookieExport;

  /// No description provided for @cookieExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败'**
  String get cookieExportFailed;

  /// No description provided for @categoryPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get categoryPermissions;

  /// No description provided for @categoryPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'隐私'**
  String get categoryPrivacy;

  /// No description provided for @showCookieKeywords.
  ///
  /// In zh, this message translates to:
  /// **'cookie 显示 隐私 凭据 key'**
  String get showCookieKeywords;

  /// No description provided for @scan.
  ///
  /// In zh, this message translates to:
  /// **'扫码'**
  String get scan;

  /// No description provided for @deleteFilesToo.
  ///
  /// In zh, this message translates to:
  /// **'同时删除文件'**
  String get deleteFilesToo;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @cookieLogin.
  ///
  /// In zh, this message translates to:
  /// **'Cookie 登录'**
  String get cookieLogin;

  /// No description provided for @permissionCamera.
  ///
  /// In zh, this message translates to:
  /// **'相机（扫码）'**
  String get permissionCamera;

  /// No description provided for @permissionCameraKeywords.
  ///
  /// In zh, this message translates to:
  /// **'camera qr scan 相机 扫码 权限'**
  String get permissionCameraKeywords;

  /// No description provided for @permissionInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装应用（打开 APK）'**
  String get permissionInstall;

  /// No description provided for @permissionInstallKeywords.
  ///
  /// In zh, this message translates to:
  /// **'install apk unknown sources 安装 未知来源 权限'**
  String get permissionInstallKeywords;

  /// No description provided for @permissionBattery.
  ///
  /// In zh, this message translates to:
  /// **'电池优化'**
  String get permissionBattery;

  /// No description provided for @permissionBatteryKeywords.
  ///
  /// In zh, this message translates to:
  /// **'battery optimization background 电池 优化 后台 权限'**
  String get permissionBatteryKeywords;

  /// No description provided for @permissionGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授权'**
  String get permissionGranted;

  /// No description provided for @permissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'未授权，点击授权'**
  String get permissionDenied;

  /// No description provided for @permissionBlocked.
  ///
  /// In zh, this message translates to:
  /// **'已被系统拒绝，需到系统设置开启'**
  String get permissionBlocked;

  /// No description provided for @permissionChecking.
  ///
  /// In zh, this message translates to:
  /// **'检查中…'**
  String get permissionChecking;

  /// No description provided for @permissionInstallGranted.
  ///
  /// In zh, this message translates to:
  /// **'已允许安装应用'**
  String get permissionInstallGranted;

  /// No description provided for @permissionInstallDenied.
  ///
  /// In zh, this message translates to:
  /// **'未允许，打开 APK 安装包前需授权'**
  String get permissionInstallDenied;

  /// No description provided for @permissionBatteryGranted.
  ///
  /// In zh, this message translates to:
  /// **'已忽略电池优化，后台传输更稳定'**
  String get permissionBatteryGranted;

  /// No description provided for @permissionBatteryRestricted.
  ///
  /// In zh, this message translates to:
  /// **'受电池优化限制，后台传输可能被中断'**
  String get permissionBatteryRestricted;

  /// No description provided for @permissionBlockedTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要到系统设置开启'**
  String get permissionBlockedTitle;

  /// No description provided for @permissionBlockedMessage.
  ///
  /// In zh, this message translates to:
  /// **'相机权限已被系统拒绝，请到系统设置中手动开启，然后回到应用。'**
  String get permissionBlockedMessage;

  /// No description provided for @permissionOpenSystemSettings.
  ///
  /// In zh, this message translates to:
  /// **'打开系统设置'**
  String get permissionOpenSystemSettings;

  /// No description provided for @permissionCameraGranted.
  ///
  /// In zh, this message translates to:
  /// **'相机权限已授权'**
  String get permissionCameraGranted;

  /// No description provided for @permissionOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开系统设置'**
  String get permissionOpenFailed;

  /// No description provided for @backupAndRestore.
  ///
  /// In zh, this message translates to:
  /// **'备份与恢复'**
  String get backupAndRestore;

  /// No description provided for @backupAndRestoreSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'本地文件与 WebDAV 云端'**
  String get backupAndRestoreSubtitle;

  /// No description provided for @backupKeywords.
  ///
  /// In zh, this message translates to:
  /// **'backup restore webdav cookie 备份 恢复 云端 导出'**
  String get backupKeywords;

  /// No description provided for @localBackup.
  ///
  /// In zh, this message translates to:
  /// **'本地备份'**
  String get localBackup;

  /// No description provided for @backupNow.
  ///
  /// In zh, this message translates to:
  /// **'立即备份'**
  String get backupNow;

  /// No description provided for @backupNowSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'导出为 JSON 备份文件'**
  String get backupNowSubtitle;

  /// No description provided for @backupSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存到 {path}'**
  String backupSaved(String path);

  /// No description provided for @restoreFromFile.
  ///
  /// In zh, this message translates to:
  /// **'从文件恢复'**
  String get restoreFromFile;

  /// No description provided for @restoreFromFileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择之前导出的备份文件'**
  String get restoreFromFileSubtitle;

  /// No description provided for @chooseBackupFile.
  ///
  /// In zh, this message translates to:
  /// **'选择备份文件'**
  String get chooseBackupFile;

  /// No description provided for @includeCookies.
  ///
  /// In zh, this message translates to:
  /// **'备份包含 Cookie'**
  String get includeCookies;

  /// No description provided for @includeCookiesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'危险！启用后，备份文件等同于登录凭据，请注意信息安全'**
  String get includeCookiesSubtitle;

  /// No description provided for @webdavSection.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV'**
  String get webdavSection;

  /// No description provided for @webdavAccount.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 账号'**
  String get webdavAccount;

  /// No description provided for @webdavServer.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 地址'**
  String get webdavServer;

  /// No description provided for @webdavServerHint.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com/dav/'**
  String get webdavServerHint;

  /// No description provided for @webdavUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get webdavUsername;

  /// No description provided for @webdavPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get webdavPassword;

  /// No description provided for @webdavNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get webdavNotSet;

  /// No description provided for @webdavBackup.
  ///
  /// In zh, this message translates to:
  /// **'云端备份'**
  String get webdavBackup;

  /// No description provided for @webdavTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get webdavTest;

  /// No description provided for @webdavTestOk.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get webdavTestOk;

  /// No description provided for @webdavUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传备份'**
  String get webdavUpload;

  /// No description provided for @webdavUploadDone.
  ///
  /// In zh, this message translates to:
  /// **'已上传 {name}'**
  String webdavUploadDone(String name);

  /// No description provided for @webdavRestore.
  ///
  /// In zh, this message translates to:
  /// **'从云端恢复'**
  String get webdavRestore;

  /// No description provided for @webdavNoBackups.
  ///
  /// In zh, this message translates to:
  /// **'云端还没有备份文件'**
  String get webdavNoBackups;

  /// No description provided for @webdavAutoBackup.
  ///
  /// In zh, this message translates to:
  /// **'自动备份'**
  String get webdavAutoBackup;

  /// No description provided for @webdavAutoBackupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'启动应用时按频率自动上传'**
  String get webdavAutoBackupSubtitle;

  /// No description provided for @webdavInterval.
  ///
  /// In zh, this message translates to:
  /// **'备份频率'**
  String get webdavInterval;

  /// No description provided for @webdavDaily.
  ///
  /// In zh, this message translates to:
  /// **'每天'**
  String get webdavDaily;

  /// No description provided for @webdavWeekly.
  ///
  /// In zh, this message translates to:
  /// **'每周'**
  String get webdavWeekly;

  /// No description provided for @lastBackupAt.
  ///
  /// In zh, this message translates to:
  /// **'上次备份：{time}'**
  String lastBackupAt(String time);

  /// No description provided for @neverBackedUp.
  ///
  /// In zh, this message translates to:
  /// **'尚未备份'**
  String get neverBackedUp;

  /// No description provided for @backupFailed.
  ///
  /// In zh, this message translates to:
  /// **'上次备份失败：{error}'**
  String backupFailed(String error);

  /// No description provided for @restoreConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'从备份恢复？'**
  String get restoreConfirmTitle;

  /// No description provided for @restoreConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'将覆盖当前设置、收藏、最近使用与快速访问；账号登录态与传输记录会保留。'**
  String get restoreConfirmMessage;

  /// No description provided for @restoreDone.
  ///
  /// In zh, this message translates to:
  /// **'已从备份恢复'**
  String get restoreDone;

  /// No description provided for @aboutVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}（构建 {build}）'**
  String aboutVersion(String version, int build);

  /// No description provided for @aboutTerms.
  ///
  /// In zh, this message translates to:
  /// **'用户协议'**
  String get aboutTerms;

  /// No description provided for @aboutPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get aboutPrivacy;

  /// No description provided for @aboutLicenses.
  ///
  /// In zh, this message translates to:
  /// **'开源许可'**
  String get aboutLicenses;

  /// No description provided for @aboutProjectHome.
  ///
  /// In zh, this message translates to:
  /// **'项目主页'**
  String get aboutProjectHome;

  /// No description provided for @termsDisclaimer.
  ///
  /// In zh, this message translates to:
  /// **'7. 免责声明：本应用是非官方的蓝奏云第三方客户端，与蓝奏云官方无任何关联，也未获得官方授权。应用按「现状」提供，因使用本应用造成的账号风险、数据丢失或服务中断由使用者自行承担。'**
  String get termsDisclaimer;

  /// No description provided for @firstRunWelcome.
  ///
  /// In zh, this message translates to:
  /// **'欢迎使用蓝云'**
  String get firstRunWelcome;

  /// No description provided for @firstRunMessage.
  ///
  /// In zh, this message translates to:
  /// **'使用前请先阅读并同意《用户协议》与《隐私政策》。'**
  String get firstRunMessage;

  /// No description provided for @agreeAndContinue.
  ///
  /// In zh, this message translates to:
  /// **'同意并继续'**
  String get agreeAndContinue;

  /// No description provided for @disagreeAndExit.
  ///
  /// In zh, this message translates to:
  /// **'不同意并退出'**
  String get disagreeAndExit;

  /// No description provided for @recentLimit.
  ///
  /// In zh, this message translates to:
  /// **'最近使用条数'**
  String get recentLimit;

  /// No description provided for @recentLimitOff.
  ///
  /// In zh, this message translates to:
  /// **'不记录'**
  String get recentLimitOff;

  /// No description provided for @recentLimitValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String recentLimitValue(int count);

  /// No description provided for @recentLimitKeywords.
  ///
  /// In zh, this message translates to:
  /// **'recent limit history 最近 条数 记录'**
  String get recentLimitKeywords;

  /// No description provided for @termsBody.
  ///
  /// In zh, this message translates to:
  /// **'《用户协议》\n\n1. 本应用是蓝奏云的非官方第三方客户端，仅供个人学习与自用，与蓝奏云官方无任何关联，也未获得官方授权或认可。\n\n2. 使用本应用需要你自己的蓝奏云账号。请勿利用本应用从事违反蓝奏云服务条款、相关法律法规或侵犯他人权益的行为。\n\n3. 本应用按「现状」提供，不提供任何形式的担保。因使用本应用造成的账号受限、数据丢失、上传或下载失败等风险，由使用者自行承担。\n\n4. 应用内使用的接口来自公开渠道与非官方整理，可能随时失效；开发者不保证功能持续可用。\n\n5. 本应用以 Apache License 2.0 开源，你可以自行修改与分发代码，但请保留原始许可与版权声明，并自行承担由此产生的责任。\n\n6. 继续使用即表示你已阅读并同意本协议；如不同意，请卸载本应用。'**
  String get termsBody;

  /// No description provided for @privacyBody.
  ///
  /// In zh, this message translates to:
  /// **'《隐私政策》\n\n1. 本应用不收集、不上传任何个人信息，没有账号系统，也没有统计、广告或崩溃上报 SDK。\n\n2. 你的蓝奏云账号（Cookie）、昵称、收藏、最近使用、传输记录与设置只保存在本机。Cookie 保存在系统加密存储中；查看 Cookie 需要先通过生物识别或锁屏验证。\n\n3. 应用运行时直接与蓝奏云官方接口通信（pc.woozooo.com、up.woozooo.com 等），请求内容仅用于完成你发起的登录、列表、上传、下载等操作。\n\n4. 分享由系统分享面板完成：只有你主动点击分享时，选中的内容或文件才会交给你选择的应用；剪贴板仅在你主动点击「复制」时写入。\n\n5. 如果你在「备份与恢复」中配置了 WebDAV，备份文件会上传到你自己填写的服务器；备份默认不包含 Cookie，是否开启与上传到哪台服务器完全由你决定。\n\n6. 相机权限仅用于扫码（当前版本尚未启用），安装应用权限仅用于打开你下载的 APK，忽略电池优化仅用于让后台传输更稳定；这些权限都可以随时在系统设置中撤销。\n\n7. 卸载应用会一并删除本机保存的账号与数据，删除前请自行备份。'**
  String get privacyBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
