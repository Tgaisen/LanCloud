// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get resolvingDownload => 'Resolving download link…';

  @override
  String get addedToQueue => 'Added to the download queue';

  @override
  String get shareNeedsPassword => 'This file requires a password';

  @override
  String resolveFailed(String error) {
    return 'Failed to resolve: $error';
  }

  @override
  String get tabHome => 'Home';

  @override
  String get tabDrive => 'Drive';

  @override
  String get tabTransfers => 'Transfers';

  @override
  String get tabProfile => 'Profile';

  @override
  String get exitTitle => 'Transfers still running';

  @override
  String exitMessage(int count) {
    return 'There are $count transfers in progress. Exiting will cancel them. Exit anyway?';
  }

  @override
  String get keepTransferring => 'Keep running';

  @override
  String get exitAndCancel => 'Exit and cancel';

  @override
  String get download => 'Download';

  @override
  String get copyLink => 'Copy link';

  @override
  String linkWithPassword(String url, String pwd) {
    return '$url Password: $pwd';
  }

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String accountUid(String uid) {
    return 'Account $uid';
  }

  @override
  String get openShareLink => 'Open share link';

  @override
  String transferringCount(int count) {
    return 'Transferring $count';
  }

  @override
  String get transferCenter => 'Transfer center';

  @override
  String get quickAccess => 'Quick access';

  @override
  String get quickAccessHint => 'Pin frequently used drive folders here';

  @override
  String get recent => 'Recent';

  @override
  String get noRecent => 'No recent items yet';

  @override
  String get sharedContent => 'Shared content';

  @override
  String get myDrive => 'My drive';

  @override
  String get myFavorites => 'Favorites';

  @override
  String get favoritesHint => 'Favorited files and shares will appear here';

  @override
  String get favoriteFolders => 'Folders';

  @override
  String get favoriteFiles => 'Files';

  @override
  String get favoriteDeleteConfirmTitle => 'Delete favorites';

  @override
  String favoriteDeleteConfirmMessage(int count) {
    return 'Remove $count selected favorites?';
  }

  @override
  String get unfavorite => 'Remove favorite';

  @override
  String get addAccount => 'Add account';

  @override
  String get lanCloudSubtitle => 'Third-party LanZou Cloud client';

  @override
  String get howToGetCookie => 'How to get your cookie';

  @override
  String get cookieSteps =>
      '1. Open and log in to the LanZou Cloud website in a browser\n2. Press F12 to open DevTools and go to the Network panel\n3. Click any request and find the Cookie in Request Headers\n4. Copy the entire value (it must include ylogin and phpdisk_info)';

  @override
  String get webLoginRecommended => 'Web login (recommended)';

  @override
  String get orPasteCookie => 'Or paste your cookie manually';

  @override
  String get lanzouCookie => 'LanZou Cloud cookie';

  @override
  String get cookieHint => 'ylogin=1234567; phpdisk_info=xxxxxx...';

  @override
  String get verifying => 'Verifying…';

  @override
  String get saveAndLogin => 'Save and log in';

  @override
  String get cookiePrivacy =>
      'The cookie is stored only on this device (encrypted system storage) and is never uploaded to any third-party server.';

  @override
  String get pleasePasteCookie => 'Paste your cookie first';

  @override
  String get cookieMissingYlogin =>
      'No ylogin field found. Make sure you copied the complete cookie.';

  @override
  String get cookieInvalid =>
      'The cookie is invalid or expired. Please get a new one.';

  @override
  String get webLogin => 'Web login';

  @override
  String get checking => 'Checking…';

  @override
  String get finishLogin => 'Finish login';

  @override
  String get webLoginGuide =>
      'Log in with your LanZou Cloud account and complete the slider check if prompted. The account is saved automatically once you reach the drive page.';

  @override
  String get noLoginDetected =>
      'No login detected yet. Complete login in the page above first.';

  @override
  String get my => 'Profile';

  @override
  String uidLabel(String uid) {
    return 'UID: $uid';
  }

  @override
  String get switchAccountShort => 'Switch';

  @override
  String get switchAccount => 'Switch account';

  @override
  String get removeCurrentAccount => 'Remove current account';

  @override
  String get settings => 'Settings';

  @override
  String get settingsSubtitle =>
      'Appearance, behavior, connections and advanced overrides';

  @override
  String get webManagement => 'Web version';

  @override
  String get webManagementSubtitle =>
      'Official features like changing your password or avatar';

  @override
  String get recycleBin => 'Recycle bin';

  @override
  String get removeAccountTitle => 'Remove account';

  @override
  String removeAccountMessage(String uid) {
    return 'This removes account $uid and its login info from this device. Files in the cloud are unaffected.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get remove => 'Remove';

  @override
  String get transfers => 'Transfers';

  @override
  String get clearFinished => 'Clear finished';

  @override
  String get upload => 'Upload';

  @override
  String get noUploads => 'No upload tasks';

  @override
  String get noDownloads => 'No download tasks';

  @override
  String get inProgress => 'In progress';

  @override
  String get finished => 'Finished';

  @override
  String get queued => 'Queued';

  @override
  String get uploading => 'Uploading';

  @override
  String get downloading => 'Downloading';

  @override
  String get completed => 'Completed';

  @override
  String failedWithError(String error) {
    return 'Failed: $error';
  }

  @override
  String get unknownError => 'Unknown error';

  @override
  String get canceled => 'Canceled';

  @override
  String get unknownSize => 'Unknown size';

  @override
  String get retry => 'Retry';

  @override
  String get open => 'Open';

  @override
  String get pleasePasteShareLink => 'Paste a LanZou Cloud share link first';

  @override
  String get addedToFavorites => 'Added to favorites';

  @override
  String get openShare => 'Open share';

  @override
  String get shareLink => 'Share link';

  @override
  String get shareLinkHint => 'https://www.lanzou.com/xxxxx';

  @override
  String get passwordOptional => 'Password (if any)';

  @override
  String get resolving => 'Resolving…';

  @override
  String get resolve => 'Resolve';

  @override
  String sizeLabel(String size) {
    return 'Size: $size';
  }

  @override
  String get favorite => 'Favorite';

  @override
  String get shareEmpty => 'This share contains no files';

  @override
  String get language => 'Language';

  @override
  String get followSystem => 'Follow system';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get themeMode => 'Theme mode';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get themeModeKeywords => 'theme night dark light';

  @override
  String get oled => 'Pure black theme';

  @override
  String get oledSubtitle =>
      'Pure black background in dark mode to save battery';

  @override
  String get oledKeywords => 'black battery oled';

  @override
  String get themeColor => 'Theme color';

  @override
  String get themeColorKeywords => 'accent color theme';

  @override
  String get classicBlue => 'Classic blue';

  @override
  String get teal => 'Teal';

  @override
  String get violet => 'Violet';

  @override
  String get vermilion => 'Vermilion';

  @override
  String get olive => 'Olive green';

  @override
  String get custom => 'Custom';

  @override
  String get hideTopBar => 'Hide top bar';

  @override
  String get hideTopBarSubtitle => 'Collapse the top bar while scrolling';

  @override
  String get hideTopBarKeywords => 'top bar hide on scroll collapse';

  @override
  String get hideBottomBar => 'Hide bottom bar';

  @override
  String get hideBottomBarSubtitle => 'Collapse the bottom bar while scrolling';

  @override
  String get hideBottomBarKeywords => 'bottom bar hide on scroll collapse';

  @override
  String get floatingNav => 'Floating nav bar';

  @override
  String get floatingNavSubtitle =>
      'Rounded with a shadow, floating above content';

  @override
  String get floatingNavKeywords => 'bottom bar floating md3';

  @override
  String get navBarItems => 'Bottom bar items';

  @override
  String get navBarItemsHint =>
      'Unchecked views stay hidden from the bottom bar and remain reachable from the home quick actions';

  @override
  String get navBarItemsKeywords =>
      'bottom bar items transfers favorites customize';

  @override
  String get swipeTabs => 'Swipe to switch views';

  @override
  String get swipeTabsSubtitle => 'Swipe left or right to switch home views';

  @override
  String get swipeTabsKeywords => 'swipe gesture tab';

  @override
  String get transitionAnimations => 'Transition animations';

  @override
  String get transitionAnimationsSubtitle =>
      'Fade-in animation when switching folders';

  @override
  String get transitionAnimationsKeywords =>
      'animation transition fade folder list';

  @override
  String get downloadDir => 'Download folder';

  @override
  String defaultDownloadDir(String path) {
    return 'Default ($path)';
  }

  @override
  String get downloadDirKeywords => 'download folder save location';

  @override
  String get launchPage => 'Default start page';

  @override
  String get launchPageKeywords => 'start home drive';

  @override
  String get homeFolderOpen => 'Open home folders in';

  @override
  String get homeFolderOpenKeywords => 'home folder open mode page drive';

  @override
  String get openInNewPage => 'New page';

  @override
  String get openInDriveTab => 'Drive tab';

  @override
  String get cacheFolders => 'Cache folder data';

  @override
  String get cacheFoldersSubtitle => 'Don\'t reload when going back a level';

  @override
  String get cacheFoldersKeywords => 'cache folder';

  @override
  String get loadAllPages => 'Auto-load all folder contents';

  @override
  String get loadAllPagesSubtitle =>
      'When off, load page by page and fetch the next page at the bottom';

  @override
  String get loadAllPagesKeywords => 'pagination load folder';

  @override
  String get requestInterval => 'Request interval';

  @override
  String requestIntervalSubtitle(int ms) {
    return '$ms ms';
  }

  @override
  String get requestIntervalHint =>
      'Default 100 ms. A smaller interval may trigger server rate limiting.';

  @override
  String get requestIntervalKeywords =>
      'interval rate limit throttling request';

  @override
  String get maxUploads => 'Concurrent uploads';

  @override
  String get uploadKeywords => 'upload concurrent';

  @override
  String get maxDownloads => 'Concurrent downloads';

  @override
  String get downloadKeywords => 'download concurrent';

  @override
  String get apiHost => 'Drive API domain';

  @override
  String get apiHostKeywords => 'domain api connection error pc up';

  @override
  String get uploadDomain => 'Upload domain';

  @override
  String get defaultUploadDomain => 'Default (up.woozooo.com)';

  @override
  String get uploadDomainKeywords => 'upload domain up';

  @override
  String get shareDomain => 'Share link domain';

  @override
  String get defaultShareDomain =>
      'Default (try built-in mirrors automatically)';

  @override
  String get shareDomainKeywords => 'share domain mirror link';

  @override
  String get userAgent => 'Custom User-Agent';

  @override
  String get defaultUserAgent => 'Default (desktop browser emulation)';

  @override
  String get userAgentKeywords => 'ua user-agent browser';

  @override
  String get advanced => 'Advanced overrides';

  @override
  String get advancedSubtitle => 'API/upload/share domains and custom UA';

  @override
  String get advancedHint =>
      'Change only when connections fail or domains are blocked; leave empty for defaults';

  @override
  String get clearRecents => 'Clear recent items';

  @override
  String get clearRecentsSubtitle => 'Remove recent items from the home page';

  @override
  String get clearRecentsKeywords => 'recent clear history';

  @override
  String get about => 'About';

  @override
  String get aboutSubtitle => 'LanCloud · Third-party LanZou Cloud client';

  @override
  String get aboutKeywords => 'version about open source license';

  @override
  String get aboutText =>
      'A personal third-party LanZou Cloud client based on unofficial APIs. Please don\'t redistribute it or use it commercially.';

  @override
  String get searchSettings => 'Search settings';

  @override
  String get closeSearch => 'Close search';

  @override
  String get searchPlaceholder =>
      'Search settings, e.g. domain, collapse, download, concurrency';

  @override
  String get noMatch => 'No matching settings';

  @override
  String get cleared => 'Cleared';

  @override
  String get restoredDefaultDir => 'Restored the default folder';

  @override
  String get restoreDefault => 'Restore default';

  @override
  String get change => 'Change';

  @override
  String downloadDirSet(String dir) {
    return 'Download folder set to $dir';
  }

  @override
  String pickDirFailed(String error) {
    return 'Failed to pick a folder: $error';
  }

  @override
  String get noInterval => 'No delay';

  @override
  String get save => 'Save';

  @override
  String get reset => 'Reset';

  @override
  String get includeWebdavAccount => 'Include WebDAV account';

  @override
  String get includeWebdavAccountSubtitle =>
      'Danger! Once enabled, the backup contains your WebDAV address and password — keep it safe';

  @override
  String get uploadDomainHint =>
      'Leave empty for the default up.woozooo.com; may include https://';

  @override
  String get shareDomainHint =>
      'Leave empty to try built-in mirrors automatically; may include https://';

  @override
  String get userAgentHint => 'Leave empty to use the default value';

  @override
  String get categoryAppearance => 'Appearance';

  @override
  String get categoryBehavior => 'Behavior';

  @override
  String get categoryConnection => 'Connection';

  @override
  String get categoryAdvanced => 'Advanced overrides';

  @override
  String get categoryData => 'Data';

  @override
  String get exitSelection => 'Exit selection';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get selectAll => 'Select all';

  @override
  String get invertSelection => 'Invert selection';

  @override
  String get newFolder => 'New folder';

  @override
  String get uploadFile => 'Upload files';

  @override
  String get uploadFileSubtitle => 'Pick files from this device or other apps';

  @override
  String uploadSkipped(int added, int skipped) {
    return 'Added $added upload tasks and skipped $skipped files larger than 100 MB';
  }

  @override
  String uploadAdded(int count) {
    return 'Added $count upload tasks';
  }

  @override
  String get nameRequired => 'Name (required)';

  @override
  String get descOptional => 'Description (optional)';

  @override
  String get create => 'Create';

  @override
  String get folderNameRequired => 'Folder name cannot be empty';

  @override
  String get deleteConfirmTitle => 'Confirm deletion';

  @override
  String deleteConfirmMessage(int count) {
    return 'Move $count selected items to the recycle bin?';
  }

  @override
  String get delete => 'Delete';

  @override
  String get folderInfo => 'Edit info';

  @override
  String get folderInfoSubtitle => 'Change name and description';

  @override
  String get accessPassword => 'Access password';

  @override
  String get accessPasswordSubtitle => 'Set or disable the access password';

  @override
  String get enablePassword => 'Enable access password';

  @override
  String get folderInfoSaved => 'Folder info updated';

  @override
  String get passwordCleared => 'Access password disabled';

  @override
  String passwordClearedCount(int count) {
    return 'Disabled access password for $count items';
  }

  @override
  String get transferDeleteConfirmTitle => 'Delete transfer records';

  @override
  String transferDeleteConfirmMessage(int count) {
    return 'Remove $count selected records (running ones will be canceled)?';
  }

  @override
  String get batchDownload => 'Batch download';

  @override
  String resolvingBatch(int count) {
    return 'Resolving and adding to the download queue ($count total)';
  }

  @override
  String addedDownloads(int count) {
    return 'Added $count download tasks';
  }

  @override
  String addedDownloadsPartial(int ok, int failed) {
    return 'Added $ok download tasks; $failed failed to resolve';
  }

  @override
  String get noLinksToCopy => 'No share links to copy';

  @override
  String passwordLabel(String pwd) {
    return 'Password: $pwd';
  }

  @override
  String favoritedCount(int count) {
    return 'Favorited $count items';
  }

  @override
  String get move => 'Move';

  @override
  String get moveSubtitle => 'Move selected files/folders to another folder';

  @override
  String get editDesc => 'Edit description';

  @override
  String get editDescBatchSubtitle =>
      'Set the description for selected files/folders';

  @override
  String get setPassword => 'Set access password';

  @override
  String get setPasswordSubtitle =>
      'Set access passwords for selected items; free accounts can only set, not remove';

  @override
  String movedTo(int count, String name) {
    return 'Moved $count items to “$name”';
  }

  @override
  String movedPartial(int ok, int failed) {
    return 'Moved $ok items; $failed failed';
  }

  @override
  String get newDescHint => 'Enter a new description';

  @override
  String get confirm => 'OK';

  @override
  String descUpdatedCount(int count) {
    return 'Updated the description of $count items';
  }

  @override
  String descUpdatedPartial(int ok, int failed) {
    return 'Updated $ok; $failed failed';
  }

  @override
  String get pwdHint => '2–6 character password';

  @override
  String get pwdTooShort => 'Password must be at least 2 characters';

  @override
  String passwordSetCount(int count) {
    return 'Set passwords for $count items';
  }

  @override
  String passwordSetPartial(int ok, int failed) {
    return 'Set $ok; $failed failed';
  }

  @override
  String get close => 'Close';

  @override
  String downloadsCount(int count) {
    return '$count downloads';
  }

  @override
  String get hasPassword => 'Has password';

  @override
  String get openLink => 'Open link';

  @override
  String get showQr => 'Show QR code';

  @override
  String get addFavorite => 'Add to favorites';

  @override
  String get moreActions => 'More actions';

  @override
  String get freeAccountPasswordNote =>
      'Free accounts can only set a password, not remove it';

  @override
  String get descUpdated => 'Description updated';

  @override
  String get passwordSet => 'Password set';

  @override
  String get favorited => 'Favorited';

  @override
  String get share => 'Share';

  @override
  String get more => 'More';

  @override
  String get add => 'Add';

  @override
  String get searchCurrentFolder => 'Search this folder';

  @override
  String get search => 'Search';

  @override
  String get menu => 'Menu';

  @override
  String get layout => 'Layout';

  @override
  String get grid => 'Grid';

  @override
  String get list => 'List';

  @override
  String get sort => 'Sort';

  @override
  String get sortName => 'Name';

  @override
  String get sortSize => 'Size';

  @override
  String get sortTime => 'Time';

  @override
  String get folderProperties => 'Folder details';

  @override
  String get sortByName => 'Sort by name';

  @override
  String get sortBySize => 'Sort by size';

  @override
  String get sortByTime => 'Sort by time';

  @override
  String get toggleLayout => 'Toggle layout style';

  @override
  String get multiSelect => 'Select';

  @override
  String get refresh => 'Refresh';

  @override
  String get root => 'Root';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String noMatchContent(String query) {
    return 'Nothing matches “$query”';
  }

  @override
  String get emptyFolder => 'This folder is empty';

  @override
  String get reachedEnd => 'You\'ve reached the end';

  @override
  String get filterResult => 'Filtered results';

  @override
  String get folderActions => 'Folder actions';

  @override
  String get fileActions => 'File actions';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get folder => 'Folder';

  @override
  String fileCount(int count) {
    return '$count files';
  }

  @override
  String get openFolder => 'Open folder';

  @override
  String get chooseTargetFolder => 'Choose destination folder';

  @override
  String get parentFolder => 'Up one level';

  @override
  String get moveHere => 'Move here';

  @override
  String get noSubfolders => 'No subfolders in this folder';

  @override
  String get notifications => 'Notifications';

  @override
  String get notifProgress => 'Transfer progress';

  @override
  String get notifProgressSubtitle =>
      'Show progress in the notification shade while transferring';

  @override
  String get notifProgressKeywords => 'notification progress transfer';

  @override
  String get notifDone => 'Completion alerts';

  @override
  String get notifDoneSubtitle =>
      'Notify when a download or upload finishes or fails';

  @override
  String get notifDoneKeywords => 'notification complete alert';

  @override
  String get notifPermission => 'Notification permission';

  @override
  String get notifPermissionKeywords => 'notification permission allow';

  @override
  String get notifPermissionChecking => 'Checking…';

  @override
  String get notifPermissionGranted => 'Granted';

  @override
  String get notifPermissionDenied => 'Not granted';

  @override
  String get notifPermissionDeniedHint =>
      'Notifications are disabled. Enable them in system settings.';

  @override
  String get notifProgressTitle => 'Transferring';

  @override
  String notifProgressBody(int count) {
    return '$count tasks in progress';
  }

  @override
  String get notifUploadDone => 'Upload complete';

  @override
  String get notifDownloadDone => 'Download complete';

  @override
  String get notifFailed => 'Transfer failed';

  @override
  String get notifChannelProgress => 'Transfer progress';

  @override
  String get notifChannelProgressDesc =>
      'Progress of downloads and uploads in progress';

  @override
  String get notifChannelDone => 'Transfers finished';

  @override
  String get notifChannelDoneDesc =>
      'Alerts when downloads and uploads finish or fail';

  @override
  String get files => 'Files';

  @override
  String get shareMessage => 'Message from the sharer';

  @override
  String favoritedPartial(int ok, int failed) {
    return '$ok favorited, $failed failed';
  }

  @override
  String get file => 'File';

  @override
  String sharerLabel(String name) {
    return 'Shared by $name';
  }

  @override
  String get editInfo => 'Edit info';

  @override
  String get favoriteTitle => 'Custom title';

  @override
  String get favoriteTitleHint => 'Leave empty to use the default name';

  @override
  String get shareInvalid =>
      'This share is no longer available (canceled or deleted)';

  @override
  String get manage => 'Manage';

  @override
  String get logout => 'Log out';

  @override
  String get appName => 'LanCloud';

  @override
  String shareReceivedFiles(int count) {
    return 'Received $count files; starting upload';
  }

  @override
  String get shareTargetUnsupported => 'Unrecognized shared content';

  @override
  String get uploadHere => 'Upload here';

  @override
  String get uploadFromApp => 'Upload from apps';

  @override
  String uploadTasksAdded(int count) {
    return 'Added $count upload tasks';
  }

  @override
  String get install => 'Install';

  @override
  String notifDoneCount(int count) {
    return '$count completed';
  }

  @override
  String get addToQuickAccess => 'Add to quick access';

  @override
  String get removeFromQuickAccess => 'Remove from quick access';

  @override
  String get unpin => 'Unpin';

  @override
  String get moveToTop => 'Move to top';

  @override
  String get expand => 'Expand';

  @override
  String get collapse => 'Collapse';

  @override
  String get copy => 'Copy';

  @override
  String get continueLabel => 'Continue';

  @override
  String get showCookie => 'Show cookie';

  @override
  String get showCookieSubtitle =>
      'Requires biometric or screen-lock verification';

  @override
  String get cookieRiskTitle => 'Show cookie?';

  @override
  String get cookieRiskMessage =>
      'The cookie is your account credential. Anyone who has it can sign in and operate your cloud drive. Don\'t screenshot, forward, or paste it into untrusted devices or apps.';

  @override
  String get cookieAuthReason => 'Verify your identity to continue';

  @override
  String get authVerifyTitle => 'Verify identity';

  @override
  String get authVerifyHint => 'Use your fingerprint or screen lock';

  @override
  String get cookieAuthFailed =>
      'Verification failed; the cookie will not be shown';

  @override
  String get cookieAuthUnavailable =>
      'No screen lock or biometrics is set up on this device, so identity can\'t be verified';

  @override
  String get cookieSheetTitle => 'Account cookie';

  @override
  String get cookieExport => 'Export';

  @override
  String get cookieExportFailed => 'Export failed';

  @override
  String get categoryPermissions => 'Permissions';

  @override
  String get categoryPrivacy => 'Privacy';

  @override
  String get showCookieKeywords => 'cookie show privacy credential key';

  @override
  String get exportLogs => 'Export runtime logs';

  @override
  String get exportLogsSubtitle =>
      'Kept on this device, export only when reporting a problem';

  @override
  String get exportLogsKeywords => 'log export share debug feedback';

  @override
  String get exportLogsEmpty => 'No logs to export yet';

  @override
  String get exportLogsFailed => 'Failed to export logs';

  @override
  String get scan => 'Scan QR code';

  @override
  String get scanTakePhoto => 'Take a photo';

  @override
  String get scanTakePhotoSubtitle =>
      'Use the system camera (no permission needed)';

  @override
  String get scanFromGallery => 'Choose from gallery';

  @override
  String get scanFromGallerySubtitle => 'Pick a QR image from the gallery';

  @override
  String get scanDecoding => 'Recognizing…';

  @override
  String get scanNoCameraApp => 'No camera app found';

  @override
  String get scanNoQrFound => 'No QR code found in the image';

  @override
  String get scanImageFailed => 'Failed to read the image';

  @override
  String get scanNotLanzou => 'No LanCloud share link found';

  @override
  String get dynamicColor => 'Dynamic color';

  @override
  String get dynamicColorSubtitle =>
      'Use colors from the system wallpaper (Android 12+)';

  @override
  String get dynamicColorUnsupported =>
      'Dynamic color is not supported on this system';

  @override
  String get dynamicColorKeywords => 'dynamic color monet wallpaper theme';

  @override
  String get clipboardLinkPrompt => 'Detect clipboard links';

  @override
  String get clipboardLinkPromptSubtitle =>
      'Prompt to open after copying a LanCloud share link';

  @override
  String get clipboardLinkPromptKeywords => 'clipboard copy link prompt';

  @override
  String get clipboardLinkFound => 'LanCloud share link detected';

  @override
  String get manageDefaultLinks => 'Manage default links';

  @override
  String get manageDefaultLinksSubtitle =>
      'Let LanCloud open share links in system settings';

  @override
  String get manageDefaultLinksKeywords => 'default links open with permission';

  @override
  String get deleteFilesToo => 'Also delete the downloaded files';

  @override
  String get login => 'Sign in';

  @override
  String get cookieLogin => 'Cookie login';

  @override
  String get permissionInstall => 'Install apps (open APK)';

  @override
  String get permissionInstallKeywords =>
      'install apk unknown sources permission';

  @override
  String get permissionBattery => 'Battery optimization';

  @override
  String get permissionBatteryKeywords =>
      'battery optimization background permission';

  @override
  String get permissionChecking => 'Checking…';

  @override
  String get permissionInstallGranted => 'Installing apps is allowed';

  @override
  String get permissionInstallDenied =>
      'Not allowed; required before opening APK installers';

  @override
  String get permissionBatteryGranted =>
      'Exempt from battery optimization; background transfers are stable';

  @override
  String get permissionBatteryRestricted =>
      'Restricted by battery optimization; background transfers may be interrupted';

  @override
  String get permissionOpenFailed => 'Unable to open system settings';

  @override
  String get backupAndRestore => 'Backup & restore';

  @override
  String get backupAndRestoreSubtitle => 'Local files and WebDAV';

  @override
  String get backupKeywords => 'backup restore webdav cookie export';

  @override
  String get localBackup => 'Local backup';

  @override
  String get backupNow => 'Back up now';

  @override
  String get backupNowSubtitle => 'Export a JSON backup file';

  @override
  String backupSaved(String path) {
    return 'Saved to $path';
  }

  @override
  String get restoreFromFile => 'Restore from file';

  @override
  String get restoreFromFileSubtitle => 'Pick a previously exported backup';

  @override
  String get chooseBackupFile => 'Choose backup file';

  @override
  String get includeCookies => 'Include cookies';

  @override
  String get includeCookiesSubtitle =>
      'Danger! Once enabled, the backup file is equivalent to your login credential — keep it safe';

  @override
  String get webdavSection => 'WebDAV';

  @override
  String get webdavAccount => 'WebDAV account';

  @override
  String get webdavServer => 'WebDAV URL';

  @override
  String get webdavServerHint => 'https://example.com/dav/';

  @override
  String get webdavUsername => 'Username';

  @override
  String get webdavPassword => 'Password';

  @override
  String get webdavNotSet => 'Not set';

  @override
  String get webdavBackup => 'Cloud backup';

  @override
  String get webdavTest => 'Test connection';

  @override
  String get webdavTestOk => 'Connected';

  @override
  String get webdavUpload => 'Upload backup';

  @override
  String webdavUploadDone(String name) {
    return 'Uploaded $name';
  }

  @override
  String get webdavRestore => 'Restore from cloud';

  @override
  String get webdavNoBackups => 'No backups in the cloud yet';

  @override
  String get webdavAutoBackup => 'Auto backup';

  @override
  String get webdavAutoBackupSubtitle => 'Upload automatically at launch';

  @override
  String get webdavInterval => 'Backup frequency';

  @override
  String get webdavDaily => 'Daily';

  @override
  String get webdavWeekly => 'Weekly';

  @override
  String lastBackupAt(String time) {
    return 'Last backup: $time';
  }

  @override
  String get neverBackedUp => 'Not yet';

  @override
  String backupFailed(String error) {
    return 'Last backup failed: $error';
  }

  @override
  String get restoreConfirmTitle => 'Restore from backup?';

  @override
  String get restoreConfirmMessage =>
      'This overwrites settings, favorites, recents and quick access; your sign-in and transfer history are kept.';

  @override
  String get restoreDone => 'Restored from backup';

  @override
  String aboutVersion(String version, int build) {
    return 'Version $version (build $build)';
  }

  @override
  String get aboutTerms => 'Terms of service';

  @override
  String get aboutPrivacy => 'Privacy policy';

  @override
  String get aboutLicenses => 'Open-source licenses';

  @override
  String get aboutProjectHome => 'Project home';

  @override
  String get termsDisclaimer =>
      '7. Disclaimer: this is an unofficial third-party LanZou Cloud client, not affiliated with or endorsed by LanZou. It is provided \"as is\"; account risks, data loss or service interruptions are at your own risk.';

  @override
  String get firstRunWelcome => 'Welcome to LanCloud';

  @override
  String get firstRunMessage =>
      'Please read and accept the Terms of Service and Privacy Policy before continuing.';

  @override
  String get agreeAndContinue => 'Agree and continue';

  @override
  String get disagreeAndExit => 'Decline and exit';

  @override
  String get recentLimit => 'Recent items limit';

  @override
  String get recentLimitOff => 'Don\'t record';

  @override
  String recentLimitValue(int count) {
    return '$count items';
  }

  @override
  String get recentLimitKeywords => 'recent limit history';

  @override
  String get termsBody =>
      'Terms of Service\n\n1. This is an unofficial third-party LanZou Cloud client for personal use. It is not affiliated with, authorized by, or endorsed by LanZou.\n\n2. You use your own LanZou account. Do not use this app to violate LanZou\'s terms, applicable laws, or the rights of others.\n\n3. The app is provided \"as is\", without warranty of any kind. Risks such as account restrictions, data loss, or failed uploads/downloads are yours to bear.\n\n4. The APIs used are collected from public and unofficial sources and may stop working at any time.\n\n5. The app is open source under the Apache License 2.0. You may modify and redistribute the code, keeping the original license and copyright notices.\n\n6. Continuing to use the app means you have read and accepted these terms; if not, please uninstall it.';

  @override
  String get privacyBody =>
      'Privacy Policy\n\n1. The app collects and uploads no personal data. There is no account system, analytics, ads, or crash-reporting SDK.\n\n2. Your LanZou account (cookie), nickname, favorites, recents, transfer history and settings stay on this device. The cookie is kept in encrypted system storage; viewing it requires biometric or screen-lock verification. Runtime logs (errors plus version info) are also kept on this device, and are handed to apps you choose only when you tap Export runtime logs.\n\n3. The app talks directly to official LanZou endpoints (pc.woozooo.com, up.woozooo.com, etc.); requests only serve the actions you start, such as signing in, listing, uploading or downloading.\n\n4. Sharing goes through the system share sheet: content or files are handed to the app you pick, only when you tap share. The clipboard is written only when you tap Copy; Detect clipboard links is off by default, and once you turn it on under Settings - Notifications the app reads the clipboard when returning to the foreground only to detect LanCloud share links and offer to open them, never uploading it.\n\n5. If you configure WebDAV under Backup & restore, backups are uploaded to the server you enter; cookies are excluded by default. Enabling it and choosing the server is entirely up to you.\n\n6. The camera permission is only for QR scanning, the install-apps permission is only for opening APKs you downloaded, and ignoring battery optimization only keeps background transfers stable. All can be revoked in system settings.\n\n7. Uninstalling the app deletes the accounts and data stored on this device, so back up first.';
}
