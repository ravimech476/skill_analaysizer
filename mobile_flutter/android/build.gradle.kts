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

    // Flutter pins plugin subprojects to its own compileSdk (34), but
    // flutter_plugin_android_lifecycle — reached through file_picker and image_picker —
    // requires everything depending on it to compile against 36, so file_picker failed
    // its AAR metadata check. Raising compileSdk on :app alone does not reach the
    // plugins, so every Android subproject is lifted here. compileSdk only governs which
    // APIs are visible at build time; minSdk and targetSdk stay exactly as Flutter sets
    // them. Applied by reflection so it does not bind to one Android Gradle Plugin
    // version, and registered here rather than after the evaluationDependsOn block
    // below, which would already have evaluated :app.
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            android.javaClass
                .getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(android, 36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
