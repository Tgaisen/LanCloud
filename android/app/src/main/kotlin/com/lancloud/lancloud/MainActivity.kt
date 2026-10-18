package com.lancloud.lancloud

import android.Manifest
import android.content.ClipData
import android.content.ClipDescription
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.PowerManager
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.view.DragEvent
import android.view.DragAndDropPermissions
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException

// local_auth（生物识别）要求宿主 Activity 必须是 FragmentActivity。
class MainActivity : FlutterFragmentActivity() {
    private var pickFilesResult: MethodChannel.Result? = null
    /// 拍照识别的输出文件（用 ACTION_IMAGE_CAPTURE 时由本应用创建）。
    private var photoOutputPath: String? = null
    /// 系统「保存文件」对话框（ACTION_CREATE_DOCUMENT）的等待结果与待写入文件。
    private var saveFileResult: MethodChannel.Result? = null
    private var saveSourcePath: String? = null
    /// SAF 选择下载目录（ACTION_OPEN_DOCUMENT_TREE）的等待结果。
    private var pickDirResult: MethodChannel.Result? = null
    /// SAF 通道：把文件写入用户授权目录时，主动向 Dart 侧推送复制进度。
    private var safChannel: MethodChannel? = null
    private var linksChannel: MethodChannel? = null
    private var pendingLink: String? = null
    /// 等待结果的「本地网络」权限请求（Android 17 起局域网访问需要）。
    private var localNetworkResult: MethodChannel.Result? = null
    /// 外部拖拽（其它应用 → 本应用）：原生只负责接住 Android 的 drag 事件，
    /// 解析成文本 / 文件清单后转给 Dart 侧处理。
    private var dragDropChannel: MethodChannel? = null
    private var dragActive = false
    /// 是否正在把拖入的文件复制到缓存（复制期间不撤掉 Dart 侧的高亮提示）。
    private var dropCopying = false
    /// 拖拽 URI 的临时读权限；复制完（或下一次拖拽）时释放。
    private var dropPermissions: DragAndDropPermissions? = null
    /// 监听系统动画缩放变化的观察者（要留引用，否则会被回收）。
    private var animationScaleObserver: ContentObserver? = null

    /// 系统「选择文件 / 拍照」与「保存文件」对话框的结果。
    ///
    /// Activity 的 startActivityForResult / onActivityResult 已被 Android 弃用，
    /// 改用 Activity Result API；launcher 必须在 Activity 变成 STARTED 之前注册，
    /// 因此放在字段初始化里（构造期注册），回调仍走原来的结果处理函数。
    /// 选文件与拍照共用同一个 launcher —— 与原实现共用 requestCode 的语义一致，
    /// 由 photoOutputPath 区分是不是拍照。
    private val pickFilesLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        handlePickFilesResult(activityResult.resultCode, activityResult.data)
    }
    private val saveFileLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        handleSaveFileResult(activityResult.resultCode, activityResult.data)
    }
    private val pickDirLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        handlePickDirectoryResult(activityResult.resultCode, activityResult.data)
    }

    companion object {
        private const val TAG = "LanCloudDrag"
        private const val LOCAL_NETWORK_REQUEST = 2002
        /// 蓝奏云分享链接域名：lanzoua.com ~ lanzouz.com（含 *.cn 与子域名）
        private val LANZOU_HOST =
            Regex("(^|\\.)lanzou[a-z]*\\.(com|cn)$", RegexOption.IGNORE_CASE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val installer = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/installer",
        )
        installer.setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("not_found", "file not found", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                            result.success(false)
                        } else {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileProvider",
                                file,
                            )
                            val intent = Intent(Intent.ACTION_VIEW)
                            intent.setDataAndType(
                                uri,
                                "application/vnd.android.package-archive",
                            )
                            intent.addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK,
                            )
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/file_picker",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFiles" -> {
                    pickFilesResult = result
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "*/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        try {
                            putExtra(
                                DocumentsContract.EXTRA_INITIAL_URI,
                                DocumentsContract.buildDocumentUri(
                                    "com.android.externalstorage.documents",
                                    "primary:Download",
                                ),
                            )
                        } catch (_: Exception) {
                            // 部分设备不支持初始目录，忽略即可
                        }
                    }
                    try {
                        pickFilesLauncher.launch(intent)
                    } catch (e: Exception) {
                        pickFilesResult = null
                        result.error("pick_failed", e.message, null)
                    }
                }
                // 拍照识别二维码：ACTION_IMAGE_CAPTURE（本应用不声明 CAMERA 权限，
                // 由系统相机 App 完成拍摄，因此无需申请任何权限）。
                "takePhoto" -> {
                    val dir = File(cacheDir, "photo").apply { mkdirs() }
                    val file = File(dir, "qr_${System.currentTimeMillis()}.jpg")
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.fileProvider",
                        file,
                    )
                    val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                        putExtra(MediaStore.EXTRA_OUTPUT, uri)
                        addFlags(
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    }
                    if (intent.resolveActivity(packageManager) == null) {
                        result.error("no_camera", "no camera app", null)
                        return@setMethodCallHandler
                    }
                    pickFilesResult = result
                    photoOutputPath = file.absolutePath
                    try {
                        pickFilesLauncher.launch(intent)
                    } catch (e: Exception) {
                        pickFilesResult = null
                        photoOutputPath = null
                        result.error("photo_failed", e.message, null)
                    }
                }
                // 系统「保存文件」对话框（ACTION_CREATE_DOCUMENT）：
                // 把应用私有目录里的文件写到用户选择的位置，无需存储权限。
                "saveFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "path required", null)
                        return@setMethodCallHandler
                    }
                    val source = File(path)
                    if (!source.exists()) {
                        result.error("not_found", "file not found", null)
                        return@setMethodCallHandler
                    }
                    val fileName = call.argument<String>("fileName")
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("mime") ?: "application/octet-stream"
                        if (!fileName.isNullOrEmpty()) {
                            putExtra(Intent.EXTRA_TITLE, fileName)
                        }
                        try {
                            putExtra(
                                DocumentsContract.EXTRA_INITIAL_URI,
                                DocumentsContract.buildDocumentUri(
                                    "com.android.externalstorage.documents",
                                    "primary:Download",
                                ),
                            )
                        } catch (_: Exception) {
                            // 部分设备不支持初始目录，忽略即可
                        }
                    }
                    saveFileResult = result
                    saveSourcePath = source.absolutePath
                    try {
                        saveFileLauncher.launch(intent)
                    } catch (e: Exception) {
                        saveFileResult = null
                        saveSourcePath = null
                        result.error("save_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // SAF（Storage Access Framework）目录读写：
        // 选择下载目录（持久化授权）、把下载好的文件写入授权目录、
        // 删除 / 打开这些文件。全部经 ContentResolver 走系统授予的权限，
        // 不需要任何存储权限，也不受分区存储限制。
        val saf = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/saf",
        )
        saf.setMethodCallHandler { call, result -> handleSafCall(call, result) }
        safChannel = saf
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/share",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrEmpty()) {
                        result.error("bad_args", "text required", null)
                        return@setMethodCallHandler
                    }
                    val subject = call.argument<String>("subject").orEmpty()
                    try {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                            if (subject.isNotEmpty()) {
                                putExtra(Intent.EXTRA_SUBJECT, subject)
                            }
                        }
                        val chooser = Intent.createChooser(
                            send,
                            subject.ifEmpty { null },
                        )
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("share_failed", e.message, null)
                    }
                }
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_args", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // SAF 下载的文件本身就是 content:// URI（应用持有
                        // 持久化读权限），直接分享并把读权限转授给接收方；
                        // 其它路径仍走 FileProvider。
                        val uri: Uri
                        val defaultMime: String
                        if (path.startsWith("content://")) {
                            uri = Uri.parse(path)
                            defaultMime = contentResolver.getType(uri) ?: "*/*"
                        } else {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("not_found", "file not found", null)
                                return@setMethodCallHandler
                            }
                            uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileProvider",
                                file,
                            )
                            defaultMime = "application/octet-stream"
                        }
                        val subject = call.argument<String>("subject").orEmpty()
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = call.argument<String>("mime") ?: defaultMime
                            putExtra(Intent.EXTRA_STREAM, uri)
                            if (subject.isNotEmpty()) {
                                putExtra(Intent.EXTRA_SUBJECT, subject)
                            }
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        val chooser = Intent.createChooser(
                            send,
                            subject.ifEmpty { null },
                        )
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("share_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/permissions",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "install" to installPermissionStatus(),
                        "battery" to batteryPermissionStatus(),
                    ),
                )
                "openInstallSettings" -> result.success(openInstallSettings())
                "requestBattery" -> result.success(requestBatteryOptimization())
                "requestLocalNetwork" -> requestLocalNetworkPermission(result)
                "openAppSettings" -> result.success(openAppSettings())
                "openDefaultLinksSettings" ->
                    result.success(openDefaultLinksSettings())
                else -> result.notImplemented()
            }
        }
        // 外部用蓝奏云分享链接打开本应用（intent-filter）。
        val links = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/links",
        )
        links.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    val link = pendingLink ?: linkFromIntent(intent)
                    pendingLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }
        linksChannel = links
        linkFromIntent(intent)?.let { pendingLink = it }

        // 外部链接（http / https）：优先交给浏览器的 Custom Tabs 打开。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/external_link",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openCustomTab" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("bad_args", "url required", null)
                        return@setMethodCallHandler
                    }
                    result.success(openExternalCustomTab(url))
                }
                else -> result.notImplemented()
            }
        }

        // 系统「移除动画 / 减弱动态效果」与「读屏接管交互」：
        //
        // - 动画缩放：Flutter 引擎只读 transition_animation_scale，而华为等 ROM
        //   的无障碍开关只改 window / animator 两个 scale，引擎那边读不到；
        //   这里把三项都读出来报给 Dart 侧，变化时主动推送。
        // - 触摸探索（TalkBack / 屏幕朗读）：引擎给 Dart 的 accessibleNavigation
        //   是**任何**无障碍服务查一次语义树就会被置位的标志（自动记账、自动填表
        //   这类服务也会），不能当「要求少动效」用；这里改成看
        //   AccessibilityManager.isTouchExplorationEnabled()——只有真正的读屏
        //   才会开触摸探索。
        val systemChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/system",
        )
        systemChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "motionState" -> result.success(systemMotionState())
                // Android SDK（API）级别：WebView 的合成方式按它判定
                //（Hybrid Composition 只在 Android 10+ 启用，见 web_page.dart）
                "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                // 设备支持的 ABI（按优先级）：更新检测据此挑对应架构的安装包
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                // 设备 / 系统信息：「关于 - 相关信息」反馈用。
                // versionCode 取系统里实际安装的包（拆分包按 ABI 加了偏移，
                // 和 pubspec 里的基准号不同），反馈时以这个为准。
                "deviceInfo" -> {
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    val installedVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION")
                        val legacyCode = packageInfo.versionCode
                        legacyCode.toLong()
                    }
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "release" to Build.VERSION.RELEASE,
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "display" to Build.DISPLAY,
                            "abis" to Build.SUPPORTED_ABIS.toList(),
                            "versionCode" to installedVersionCode,
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }
        observeMotionState(systemChannel)
        setupDragDrop(flutterEngine)
    }

    private fun accessibilityManager(): AccessibilityManager? =
        getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager

    /// 三个动画缩放任一为 0 → 系统要求「移除动画」。
    private fun systemReduceMotion(): Boolean {
        return animationScaleKeys().any { key ->
            try {
                Settings.Global.getFloat(contentResolver, key, 1f) == 0f
            } catch (_: Exception) {
                false
            }
        }
    }

    /// 当前是否要求少动效的两项依据：动画缩放 + 触摸探索（真正的读屏）。
    private fun systemMotionState(): Map<String, Boolean> = mapOf(
        "reduceMotion" to systemReduceMotion(),
        "touchExploration" to (accessibilityManager()?.isTouchExplorationEnabled == true),
    )

    private fun animationScaleKeys(): List<String> = listOf(
        Settings.Global.TRANSITION_ANIMATION_SCALE,
        Settings.Global.WINDOW_ANIMATION_SCALE,
        Settings.Global.ANIMATOR_DURATION_SCALE,
    )

    /// 用户改动画缩放 / 开关读屏时立即通知 Dart 侧（不必重启应用）。
    private fun observeMotionState(channel: MethodChannel) {
        fun push() {
            try {
                channel.invokeMethod("motionStateChanged", systemMotionState())
            } catch (_: Exception) {
                // Dart 侧还没准备好时忽略
            }
        }
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                push()
            }
        }
        for (key in animationScaleKeys()) {
            try {
                contentResolver.registerContentObserver(
                    Settings.Global.getUriFor(key),
                    false,
                    observer,
                )
            } catch (_: Exception) {
                // 个别 ROM 不允许注册，忽略即可（还有启动/回前台时的主动读取）
            }
        }
        try {
            accessibilityManager()?.addTouchExplorationStateChangeListener { push() }
        } catch (_: Exception) {
            // 拿不到 AccessibilityManager 时忽略（还有启动/回前台时的主动读取）
        }
        animationScaleObserver = observer
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = linkFromIntent(intent) ?: return
        val channel = linksChannel
        if (channel == null) {
            pendingLink = link
        } else {
            channel.invokeMethod("link", link)
        }
    }

    /// 只接受 http(s) 的蓝奏云分享链接。
    private fun linkFromIntent(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        val host = uri.host?.lowercase() ?: return null
        if (!LANZOU_HOST.containsMatchIn(host)) return null
        return uri.toString()
    }

    /// granted / denied（Android 8 以下默认允许）
    private fun installPermissionStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "granted"
        return if (packageManager.canRequestPackageInstalls()) "granted" else "denied"
    }

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return startSafely(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    /// granted / denied（Android 6 以下默认不受电池优化限制）
    private fun batteryPermissionStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "granted"
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return if (power.isIgnoringBatteryOptimizations(packageName)) {
            "granted"
        } else {
            "denied"
        }
    }

    private fun requestBatteryOptimization(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val request = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"),
        )
        if (startSafely(request)) return true
        // 部分 ROM 不提供上面这个弹窗入口，退回到电池优化列表
        return startSafely(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    private fun openAppSettings(): Boolean = startSafely(
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        ),
    )

  /// 默认打开链接设置：Android 12+ 有独立入口，低版本退到应用详情页。
    /// 默认打开链接设置：Android 12+ 有独立入口，低版本退到应用详情页。
    private fun openDefaultLinksSettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS,
            Uri.parse("package:$packageName"),
        )
        return startSafely(intent) || openAppSettings()
    }

    private fun startSafely(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /// 请求「本地网络」权限：Android 17（API 37）起 targetSdk 37 的应用
    /// 默认无法访问局域网，需要在访问前拿到该权限；低版本直接视为已授权。
    private fun requestLocalNetworkPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 37) {
            result.success(true)
            return
        }
        val granted = checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        // 同一时间只处理一个请求，重复调用直接返回上一次的结果
        localNetworkResult?.success(false)
        localNetworkResult = result
        requestPermissions(
            arrayOf(Manifest.permission.ACCESS_LOCAL_NETWORK),
            LOCAL_NETWORK_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCAL_NETWORK_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        localNetworkResult?.success(granted)
        localNetworkResult = null
    }

    // 不再覆写 onActivityResult：本应用自己的系统对话框走 Activity Result API，
    // 插件的回调由 FlutterFragmentActivity 自己转发。
    private fun handlePickFilesResult(resultCode: Int, data: Intent?) {
        val result = pickFilesResult
        pickFilesResult = null
        if (result == null) return
        // 拍照：输出文件是本应用创建的，成功即返回该路径；取消则删掉空文件。
        val photoPath = photoOutputPath
        photoOutputPath = null
        if (photoPath != null) {
            if (resultCode == RESULT_OK) {
                result.success(listOf(photoPath))
            } else {
                File(photoPath).delete()
                result.success(emptyList<String>())
            }
            return
        }
        if (resultCode != RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }
        val uris = mutableListOf<Uri>()
        data.data?.let { uris.add(it) }
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(i).uri)
            }
        }
        result.success(uris.mapNotNull { copyToCache(it) })
    }

    /// 把待导出文件的内容写入用户在系统「保存文件」对话框里选中的位置。
    private fun handleSaveFileResult(resultCode: Int, data: Intent?) {
        val result = saveFileResult
        saveFileResult = null
        val sourcePath = saveSourcePath
        saveSourcePath = null
        if (result == null) return
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || sourcePath == null) {
            // 用户取消：不写入，Dart 侧收到 null
            result.success(null)
            return
        }
        try {
            val out = contentResolver.openOutputStream(uri)
            if (out == null) {
                result.error("save_failed", "cannot open target", null)
                return
            }
            out.use { output ->
                File(sourcePath).inputStream().use { input ->
                    input.copyTo(output)
                }
            }
            result.success(queryDisplayName(uri) ?: File(sourcePath).name)
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    // -------------------------------------------------------------------- SAF

    /// SAF 通道入口：选目录 / 导出文件 / 删除 / 打开。
    private fun handleSafCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> {
                // 上一次请求还没回来（理论上不会发生）：当作取消处理
                pickDirResult?.success(null)
                pickDirResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                    )
                    val initial = call.argument<String>("initialUri")
                    if (!initial.isNullOrEmpty() &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ) {
                        try {
                            putExtra(
                                DocumentsContract.EXTRA_INITIAL_URI,
                                Uri.parse(initial),
                            )
                        } catch (_: Exception) {
                            // 个别 ROM 不支持初始目录，忽略即可
                        }
                    }
                }
                try {
                    pickDirLauncher.launch(intent)
                } catch (e: Exception) {
                    pickDirResult = null
                    result.error("pick_failed", e.message, null)
                }
            }
            "releaseDirectory" -> {
                releaseSafTree(call.argument<String>("uri"))
                result.success(null)
            }
            "exportFile" -> exportToSafTree(call, result)
            "deleteFile" -> deleteSafDocument(call.argument<String>("uri"), result)
            "openFile" -> openSafDocument(call.argument<String>("uri"), result)
            else -> result.notImplemented()
        }
    }

    /// 用户在系统目录选择器里选定目录：
    /// - Download、Documents 等标准公共目录可以直接按文件路径写入
    ///   （Android 11+），返回 `{uri, label, path}`，不占用持久化授权；
    /// - 其它目录拿到持久化读写授权后返回 `{uri, label}`；
    /// - 用户取消返回 null。
    private fun handlePickDirectoryResult(resultCode: Int, data: Intent?) {
        val result = pickDirResult
        pickDirResult = null
        if (result == null) return
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return
        }
        val direct = directPathForTree(uri)
        if (direct != null && canWriteDirectly(direct)) {
            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "label" to direct,
                    "path" to direct,
                ),
            )
            return
        }
        try {
            val takeFlags = (data?.flags ?: 0) and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, takeFlags)
            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "label" to safTreeLabel(uri),
                ),
            )
        } catch (e: Exception) {
            result.error("pick_failed", e.message, null)
        }
    }

    /// 选中的目录是主存储上的标准公共目录时，返回可直接写入的真实路径；
    /// 其它情况（二级存储 / 非公共目录 / Android 10）返回 null，需要走 SAF。
    private fun directPathForTree(uri: Uri): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val docId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (_: Exception) {
            return null
        }
        when (uri.authority) {
            "com.android.externalstorage.documents" -> {
                val sep = docId.indexOf(':')
                if (sep <= 0) return null
                if (docId.substring(0, sep) != "primary") return null
                val relative = docId.substring(sep + 1)
                val top = relative.substringBefore('/')
                if (top.isEmpty() || !isWritableStandardDir(top)) return null
                return "${Environment.getExternalStorageDirectory().absolutePath}/$relative"
            }
            // 侧栏「Downloads」快捷入口：映射到主存储的 Download 目录
            "com.android.providers.downloads.documents" -> {
                if (docId != "downloads") return null
                return File(
                    Environment.getExternalStorageDirectory(),
                    Environment.DIRECTORY_DOWNLOADS,
                ).absolutePath
            }
        }
        return null
    }

    /// 标准公共目录（Download、Documents、DCIM 等）里应用可以直接创建
    /// 自己的文件；其余目录受分区存储限制。个别设备目录名大小写不一致，
    /// 统一按小写判断（到底能不能写由 [canWriteDirectly] 探针复核）。
    private fun isWritableStandardDir(name: String): Boolean =
        name.lowercase() in setOf(
            "music", "podcasts", "ringtones", "alarms", "notifications",
            "pictures", "movies", "download", "dcim", "documents",
            "audiobooks", "recordings",
        )

    /// 真写一个探针文件，确认这个目录确实可以按路径写入
    /// （不通过时 [handlePickDirectoryResult] 会退回 SAF 授权流程）。
    private fun canWriteDirectly(path: String): Boolean {
        val probe = File(path, ".lancloud_probe_${System.currentTimeMillis()}")
        return try {
            val created = probe.createNewFile()
            if (created) probe.delete()
            created
        } catch (_: Exception) {
            false
        }
    }

    /// 释放不再使用的目录授权（换目录 / 恢复默认时调用）。
    private fun releaseSafTree(uriStr: String?) {
        if (uriStr.isNullOrEmpty()) return
        try {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(uriStr),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: Exception) {
            // 没持有过（例如备份恢复到另一台设备）：忽略
        }
    }

    /// 目录的展示名：内部存储转成 /storage/emulated/0/xxx 这样的路径，
    /// 其它存储卷 / 提供方退回系统给的目录显示名。
    private fun safTreeLabel(uri: Uri): String {
        val docId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (_: Exception) {
            null
        }
        val displayName = try {
            val docUri = DocumentsContract.buildDocumentUriUsingTree(uri, docId.orEmpty())
            contentResolver.query(
                docUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
        val id = docId ?: return displayName ?: uri.toString()
        val sep = id.indexOf(':')
        if (sep <= 0) return displayName ?: id
        val volume = id.substring(0, sep)
        val relative = id.substring(sep + 1)
        return if (volume == "primary") {
            "${Environment.getExternalStorageDirectory().absolutePath}/$relative"
        } else {
            "$volume/$relative"
        }
    }

    /// 把应用专属目录里下载好的文件写入用户授权的目录：
    /// 先查目标目录已有名字去重（沿用 Dart 侧 `name(1).ext` 的规则），
    /// 再 createDocument + 流式复制，复制中向 Dart 侧推送进度。
    private fun exportToSafTree(call: MethodCall, result: MethodChannel.Result) {
        val treeUriStr = call.argument<String>("treeUri")
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        if (treeUriStr.isNullOrEmpty() || sourcePath.isNullOrEmpty() || fileName.isNullOrEmpty()) {
            result.error("bad_args", "treeUri, sourcePath and fileName are required", null)
            return
        }
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val jobId = call.argument<String>("jobId").orEmpty()
        Thread {
            doExportToSafTree(treeUriStr, sourcePath, fileName, mime, jobId, result)
        }.start()
    }

    /// 复制本体；放在后台线程里执行（由 [exportToSafTree] 调用）。
    private fun doExportToSafTree(
        treeUriStr: String,
        sourcePath: String,
        fileName: String,
        mime: String,
        jobId: String,
        result: MethodChannel.Result,
    ) {
        try {
            val source = File(sourcePath)
            if (!source.exists()) {
                postSafError(result, "not_found", "source file not found")
                return
            }
            val treeUri = Uri.parse(treeUriStr)
            val treeDocId = DocumentsContract.getTreeDocumentId(treeUri)
            val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeDocId)
            val existing = mutableSetOf<String>()
            try {
                contentResolver.query(
                    childrenUri,
                    arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        cursor.getString(0)?.let { existing.add(it) }
                    }
                }
            } catch (_: Exception) {
                // 查询失败时按原名创建，重名交给系统处理
            }
            val targetName = uniqueSafName(existing, fileName)
            val created = DocumentsContract.createDocument(
                contentResolver,
                parentDocUri,
                mime,
                targetName,
            ) ?: throw IOException("createDocument returned null")
            val total = source.length()
            var copied = 0L
            contentResolver.openOutputStream(created)?.use { output ->
                FileInputStream(source).use { input ->
                    val buffer = ByteArray(128 * 1024)
                    var lastTick = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        copied += read
                        val now = SystemClock.elapsedRealtime()
                        if (jobId.isNotEmpty() && now - lastTick >= 120) {
                            lastTick = now
                            postSafProgress(jobId, copied, total)
                        }
                    }
                }
            } ?: throw IOException("openOutputStream returned null")
            if (jobId.isNotEmpty()) postSafProgress(jobId, copied, total)
            runOnUiThread {
                result.success(mapOf("uri" to created.toString(), "name" to targetName))
            }
        } catch (e: SecurityException) {
            postSafError(result, "perm_denied", e.message)
        } catch (e: Exception) {
            postSafError(result, "export_failed", e.message)
        }
    }

    /// 目标目录里有同名文件时，按 `name(1).ext` 规则找一个没被占用的名字。
    private fun uniqueSafName(existing: Set<String>, name: String): String {
        if (!existing.contains(name)) return name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var index = 1
        while (true) {
            val candidate = "$base($index)$ext"
            if (!existing.contains(candidate)) return candidate
            index++
        }
    }

    private fun deleteSafDocument(uriStr: String?, result: MethodChannel.Result) {
        if (uriStr.isNullOrEmpty()) {
            result.error("bad_args", "uri required", null)
            return
        }
        Thread {
            try {
                val deleted = DocumentsContract.deleteDocument(contentResolver, Uri.parse(uriStr))
                runOnUiThread { result.success(deleted) }
            } catch (e: Exception) {
                postSafError(result, "delete_failed", e.message)
            }
        }.start()
    }

    /// 用系统默认程序打开 SAF 文件（把读权限转授给目标应用）。
    private fun openSafDocument(uriStr: String?, result: MethodChannel.Result) {
        if (uriStr.isNullOrEmpty()) {
            result.error("bad_args", "uri required", null)
            return
        }
        try {
            val uri = Uri.parse(uriStr)
            val mime = contentResolver.getType(uri) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(packageManager) == null) {
                result.success(false)
                return
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("open_failed", e.message, null)
        }
    }

    private fun postSafError(result: MethodChannel.Result, code: String, message: String?) {
        runOnUiThread { result.error(code, message, null) }
    }

    private fun postSafProgress(jobId: String, copied: Long, total: Long) {
        Handler(Looper.getMainLooper()).post {
            try {
                safChannel?.invokeMethod(
                    "progress",
                    mapOf("id" to jobId, "copied" to copied, "total" to total),
                )
            } catch (_: Exception) {
                // Dart 侧还没注册处理器时忽略
            }
        }
    }

    // ------------------------------------------------- 外部链接（Custom Tabs）

    /// 用 Custom Tabs 打开外部链接；返回 false 表示本机不适合走 Custom Tabs，
    /// 由 Dart 侧落回 url_launcher（普通浏览器打开）。
    ///
    /// 判定口径与 url_launcher 的 inAppBrowserView 一致：CustomTabsClient 的
    /// 首选包就是「默认浏览器」——它不支持 Custom Tabs（国内 ROM 自带浏览器
    /// 大多如此）时返回 null。这种情况保持原来的「交给默认浏览器」行为，
    /// 不硬切到用户没在用的浏览器（如已装但非默认的 Chrome）。
    private fun openExternalCustomTab(url: String): Boolean {
        val uri = Uri.parse(url)
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return false
        val packageName = try {
            CustomTabsClient.getPackageName(this, null)
        } catch (e: Exception) {
            Log.w(TAG, "custom tabs lookup failed: ${e.message}")
            return false
        } ?: return false
        return try {
            val intent = CustomTabsIntent.Builder().build()
            // 指定包名：否则系统可能弹出「用哪个应用打开」的选择器
            intent.intent.setPackage(packageName)
            intent.launchUrl(this, uri)
            true
        } catch (e: Exception) {
            Log.w(TAG, "custom tab launch failed: ${e.message}")
            false
        }
    }

    // ---------------------------------------------------------------- 外部拖拽

    /// 其它应用拖进本应用的通道：原生接住 Android 的 drag 事件，把文本 /
    /// 文件清单转给 Dart 侧，由 Dart 决定怎么处理（上传、收藏、打开链接…）。
    private fun setupDragDrop(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lancloud/drag_drop",
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // 拖拽给的读权限是临时的：真正要上传时先复制到应用缓存
                "copyToCache" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrEmpty()) {
                        result.error("bad_args", "uri required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val path = copyToCache(Uri.parse(uri))
                        runOnUiThread {
                            if (path == null) {
                                result.error("copy_failed", "无法读取拖入的文件", null)
                            } else {
                                result.success(path)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        dragDropChannel = channel
        // 挂到整棵视图树上：不同 ROM（例如华为）把 drag 事件派发给哪个 View
        // 不完全一致，挂全了才能保证一定收到（同一个 handler，不会重复处理）
        attachDragListeners(window.decorView)
    }

    private fun attachDragListeners(view: View) {
        view.setOnDragListener { _, event -> handleDragEvent(event) }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                attachDragListeners(view.getChildAt(i))
            }
        }
    }

    private fun handleDragEvent(event: DragEvent): Boolean {
        when (event.action) {
            DragEvent.ACTION_DRAG_STARTED -> {
                // 注意：这一阶段系统只给 ClipDescription，ClipData 要到 DROP 才有，
                // 所以这里不能按内容判断（之前用 clipData 判断导致直接拒收、拖进来没反应）；
                // 一律接住，具体能不能处理交给 Dart。
                dragActive = true
                Log.d(TAG, "drag started: ${mimeTypes(event.clipDescription)}")
                return dragActive
            }
            DragEvent.ACTION_DRAG_ENTERED -> {
                if (dragActive) {
                    notifyDragDrop("dragEntered", dragSummary(event.clipDescription))
                }
                return true
            }
            DragEvent.ACTION_DRAG_EXITED -> {
                if (dragActive) notifyDragDrop("dragExited", null)
                return true
            }
            DragEvent.ACTION_DROP -> {
                val data = event.clipData
                Log.d(TAG, "drag drop: ${data?.itemCount ?: 0} items")
                if (dragActive) {
                    // 关键：接收方必须显式请求拖拽权限，否则读 URI 会 "no access"
                    // （权限随 Activity 存活，复制完再 release）
                    dropPermissions?.release()
                    dropPermissions = try {
                        requestDragAndDropPermissions(event)
                    } catch (e: Exception) {
                        Log.w(TAG, "request drag permissions failed: ${e.message}")
                        null
                    }
                    // 拖拽授予的读权限是临时的：必须在这一刻就把文件复制到缓存，
                    // 等用户确认"上传到此"时往往已经被回收（实测会读失败）。
                    dropCopying = true
                    // 权限相关的调用（查显示名 / 打开流）同步做完，复制字节放后台
                    val items = collectDropItems(data)
                    Thread {
                        val payload = buildDropPayload(items)
                        runOnUiThread {
                            dropCopying = false
                            dropPermissions?.release()
                            dropPermissions = null
                            notifyDragDrop("dropped", payload)
                        }
                    }.start()
                }
                return true
            }
            DragEvent.ACTION_DRAG_ENDED -> {
                // 复制还没结束就别撤掉提示条（Dart 侧会一直显示到 dropped）
                if (dragActive && !dropCopying) notifyDragDrop("dragExited", null)
                dragActive = false
                return true
            }
        }
        return false
    }

    /// 拖拽内容概览（进入窗口时的高亮提示用）。
    ///
    /// 悬停阶段拿不到 ClipData，只能按 ClipDescription 的 MIME 类型判断"像不像
    /// 链接 / 文件"：1 表示这一类至少有一项，精确条数等 DROP 时再数。
    private fun dragSummary(description: ClipDescription?): Map<String, Any> {
        val types = when {
            description == null -> emptyList()
            else -> (0 until description.mimeTypeCount).map {
                description.getMimeType(it)
            }
        }
        val hasText = types.any { it.startsWith("text/") }
        val hasFiles = types.any { !it.startsWith("text/") }
        return mapOf(
            "texts" to if (hasText) 1 else 0,
            "files" to if (hasFiles) 1 else 0,
        )
    }

    /// drop 时收集到的条目：权限相关的读取（显示名 / 打开流）已经在收集阶段做完。
    private class PendingDropItem(
        val text: String?,
        val uri: String?,
        val name: String,
        val size: Long,
        val mime: String,
        val stream: java.io.InputStream?,
    )

    /// 在 drop 回调里**同步**收集内容：拖拽的 URI 读权限只在拖拽会话内有效，
    /// 查显示名、打开流都要趁现在做完（异步再读往往会 SecurityException）。
    private fun collectDropItems(data: ClipData?): List<PendingDropItem> {
        val items = mutableListOf<PendingDropItem>()
        if (data == null) return items
        for (i in 0 until data.itemCount) {
            val item = data.getItemAt(i)
            val uri = item.uri
            if (uri != null) {
                val granted = checkUriPermission(
                    uri,
                    Process.myPid(),
                    Process.myUid(),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                ) == PackageManager.PERMISSION_GRANTED
                val name = queryDisplayName(uri)
                    ?: uri.lastPathSegment?.substringAfterLast('/')
                    ?: "file"
                val stream = try {
                    contentResolver.openInputStream(uri)
                } catch (e: Exception) {
                    Log.w(TAG, "open drop uri failed: ${e.message}")
                    null
                }
                Log.d(TAG, "drop uri=$uri granted=$granted name=$name")
                items.add(
                    PendingDropItem(
                        text = null,
                        uri = uri.toString(),
                        name = name,
                        size = querySize(uri),
                        mime = contentResolver.getType(uri) ?: "",
                        stream = stream,
                    ),
                )
            } else {
                val text = item.text?.toString() ?: item.htmlText?.toString()
                if (!text.isNullOrBlank()) {
                    items.add(
                        PendingDropItem(
                            text = text,
                            uri = null,
                            name = "",
                            size = 0,
                            mime = "",
                            stream = null,
                        ),
                    )
                }
            }
        }
        return items
    }

    /// 后台把已打开的流复制到缓存，拼成给 Dart 的 payload。
    private fun buildDropPayload(items: List<PendingDropItem>): Map<String, Any> {
        val texts = mutableListOf<String>()
        val files = mutableListOf<Map<String, Any>>()
        for (item in items) {
            if (item.uri == null) {
                item.text?.let { texts.add(it) }
                continue
            }
            val path = item.stream?.let { copyStreamToCache(it, item.name) } ?: ""
            files.add(
                mapOf(
                    "uri" to item.uri,
                    "path" to path,
                    "name" to item.name,
                    "size" to item.size,
                    "mime" to item.mime,
                ),
            )
        }
        return mapOf("texts" to texts, "files" to files)
    }

    private fun querySize(uri: Uri): Long {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else 0L
            } ?: 0L
        } catch (_: Exception) {
            0L
        }
    }

    /// 把已打开的输入流写进 `cacheDir/drop`，返回本地路径。
    private fun copyStreamToCache(
        stream: java.io.InputStream,
        name: String,
    ): String? {
        return try {
            val dir = File(cacheDir, "drop").apply { mkdirs() }
            // 顺手清掉之前拖拽留下的旧文件（超过 6 小时）
            val expireAt = System.currentTimeMillis() - 6 * 60 * 60 * 1000L
            dir.listFiles()?.forEach { file ->
                if (file.lastModified() < expireAt) file.delete()
            }
            val safeName = name.ifBlank { "file" }
            val dot = safeName.lastIndexOf('.')
            val base = if (dot > 0) safeName.substring(0, dot) else safeName
            val ext = if (dot > 0) safeName.substring(dot) else ""
            var out = File(dir, safeName)
            var index = 1
            while (out.exists()) {
                out = File(dir, "$base($index)$ext")
                index += 1
            }
            stream.use { input ->
                out.outputStream().use { output -> input.copyTo(output) }
            }
            out.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "copy drop to cache failed: ${e.message}")
            null
        }
    }

    private fun notifyDragDrop(method: String, arguments: Any?) {
        try {
            dragDropChannel?.invokeMethod(method, arguments)
        } catch (_: Exception) {
            // Dart 侧还没准备好时忽略
        }
    }

    /// 悬停阶段的 MIME 类型（排查用）。
    private fun mimeTypes(description: ClipDescription?): String {
        if (description == null) return "none"
        return (0 until description.mimeTypeCount)
            .joinToString(",") { description.getMimeType(it) }
    }

    private fun copyToCache(uri: Uri): String? {
        return try {
            val displayName = queryDisplayName(uri)
                ?: "upload_${System.currentTimeMillis()}"
            val dir = File(cacheDir, "picked").apply { mkdirs() }
            val dot = displayName.lastIndexOf('.')
            val base = if (dot > 0) displayName.substring(0, dot) else displayName
            val ext = if (dot > 0) displayName.substring(dot) else ""
            var out = File(dir, displayName)
            var index = 1
            while (out.exists()) {
                out = File(dir, "$base($index)$ext")
                index++
            }
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            out.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
