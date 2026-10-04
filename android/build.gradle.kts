allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// 统一插件模块的编译版本，避免个别插件用旧 compileSdk 导致依赖校验失败。
// 注意：只处理插件模块——宿主 :app 自己按 Android 版本配置 compileSdk，
// 之前的写法会把 :app 也强制设成 36，导致 app 侧设置的 37 被覆盖。
subprojects {
    if (name == "app") return@subprojects
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            val getter = androidExtension.javaClass.methods.firstOrNull {
                it.name == "getCompileSdk" && it.parameterCount == 0
            }
            val setter = androidExtension.javaClass.methods.firstOrNull {
                it.name == "setCompileSdk" && it.parameterCount == 1
            }
            val current = (getter?.invoke(androidExtension) as? Int) ?: 0
            if (current < 36) setter?.invoke(androidExtension, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
