package com.lancloud.lancloud

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// local_auth（生物识别）要求宿主 Activity 必须是 FragmentActivity。
class MainActivity : FlutterFragmentActivity() {
    private var pickFilesResult: MethodChannel.Result? = null
    private var cameraPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val PICK_FILES_REQUEST = 2001
        private const val CAMERA_PERMISSION_REQUEST = 2003
        private const val PERMISSION_PREFS = "lancloud_permissions"
        private const val KEY_CAMERA_REQUESTED = "camera_requested"
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
                        startActivityForResult(intent, PICK_FILES_REQUEST)
                    } catch (e: Exception) {
                        pickFilesResult = null
                        result.error("pick_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
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
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("not_found", "file not found", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileProvider",
                            file,
                        )
                        val subject = call.argument<String>("subject").orEmpty()
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = call.argument<String>("mime") ?: "application/octet-stream"
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
                        "camera" to cameraPermissionStatus(),
                        "install" to installPermissionStatus(),
                        "battery" to batteryPermissionStatus(),
                    ),
                )
                "requestCamera" -> requestCameraPermission(result)
                "openInstallSettings" -> result.success(openInstallSettings())
                "requestBattery" -> result.success(requestBatteryOptimization())
                "openAppSettings" -> result.success(openAppSettings())
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_PERMISSION_REQUEST) return
        val result = cameraPermissionResult
        cameraPermissionResult = null
        result?.success(cameraPermissionStatus())
    }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    /// granted / denied / blocked（blocked = 已被系统记住拒绝，只能去系统设置开）
    private fun cameraPermissionStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "granted"
        if (hasCameraPermission()) return "granted"
        val requested = getSharedPreferences(PERMISSION_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_CAMERA_REQUESTED, false)
        if (requested && !shouldShowRequestPermissionRationale(Manifest.permission.CAMERA)) {
            return "blocked"
        }
        return "denied"
    }

    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || hasCameraPermission()) {
            result.success("granted")
            return
        }
        if (cameraPermissionResult != null) {
            result.error("in_progress", "camera permission request in progress", null)
            return
        }
        cameraPermissionResult = result
        getSharedPreferences(PERMISSION_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_CAMERA_REQUESTED, true)
            .apply()
        requestPermissions(
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST,
        )
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

    private fun startSafely(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FILES_REQUEST) return
        val result = pickFilesResult
        pickFilesResult = null
        if (result == null) return
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
