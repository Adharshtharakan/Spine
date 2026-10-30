allprojects {
    repositories {
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
// Some plugins still compile against an old Android SDK (flutter_blue_plus
// 1.34.5, pinned for its BSD licence, uses 33), which current AndroidX
// libraries reject. Raise every plugin to at least API 36. Must come before
// evaluationDependsOn(":app") so it runs before the Android plugin locks it.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        val current = runCatching { android.javaClass.getMethod("getCompileSdk").invoke(android) as Int? }.getOrNull()
            ?: runCatching {
                (android.javaClass.getMethod("getCompileSdkVersion").invoke(android) as String?)
                    ?.removePrefix("android-")?.toIntOrNull()
            }.getOrNull()
            ?: 0
        if (current < 36) {
            runCatching { android.javaClass.getMethod("setCompileSdk", Int::class.javaObjectType).invoke(android, 36) }
                .recoverCatching {
                    android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
                }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
