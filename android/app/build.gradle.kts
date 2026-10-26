import java.io.FileInputStream
import java.util.Properties
import com.android.build.api.variant.FilterConfiguration

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 签名配置：密码与密钥路径放在 android/key.properties（已在 .gitignore 中），
// 格式与备份要求见 README「签名」。缺少该文件时 release 会退回 debug 签名，仅供本地构建。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    // 用 use{} 关闭流：否则 Windows 上 Gradle daemon 会一直占着 key.properties 的句柄
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.lancloud.lancloud"
    // 适配 Android 17（API 37）：Flutter 3.47 默认还是 36，这里显式跟上最新
    compileSdk = 37

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lancloud.lancloud"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        // versionCode 来自 pubspec.yaml，存的是 ABI=0 的基准号；拆分包的实际
        // versionCode 由下面的 androidComponents 按 ABI 位加上 digit*1000
        // （见 docs/VERSIONING.md）。Flutter 自带的 ABI 偏移已由
        // android/gradle.properties 的 force-version-code-ignoring-abi=true 关掉。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
                // v2 + v3 同时写入：Android 9+ 用 v3（带密钥轮换能力，将来换签名密钥时
                // 老用户不用卸载重装），Android 7/8 继续用 v2。minSdk 24 起 v1 已无用，
                // v4 只服务 adb 增量安装，也不需要。
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = false
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // 其他机器 / CI 上没有密钥时仍能出包；正式发布前请确认签名指纹
                logger.warn("LanCloud: 缺少 android/key.properties，release 包将使用 debug 签名")
                signingConfigs.getByName("debug")
            }
        }
    }
}

// versionCode 第 6 位是 ABI（见 docs/VERSIONING.md）：
// 0 = universal（预留）/ 4 = armeabi-v7a / 7 = arm64-v8a / 8 = x86_64。
// pubspec 里存 ABI=0 的基准号，拆分包按实际 ABI 加上 digit*1000。
androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { output ->
            val abi = output.filters
                .firstOrNull {
                    it.filterType == FilterConfiguration.FilterType.ABI
                }
                ?.identifier
            val abiDigit = when (abi) {
                "armeabi-v7a" -> 4
                "arm64-v8a" -> 7
                "x86_64" -> 8
                else -> 0
            }
            if (abiDigit != 0) {
                output.versionCode.set(flutter.versionCode + abiDigit * 1000)
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // 外部链接的 Custom Tabs（MainActivity 里直接引用 androidx.browser）。
    // url_launcher / flutter_inappwebview 也依赖它，这里显式声明保证编译可见。
    implementation("androidx.browser:browser:1.10.0")
}

