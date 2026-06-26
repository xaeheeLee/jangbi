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
subprojects {
    // webview_flutter_android(카카오맵 의존)가 compileSdk 36+ 를 요구한다.
    // 일부 플러그인 모듈(kakao_map_plugin 등)이 35로 고정되어 있어 빌드가 깨지므로,
    // 플러그인 평가가 끝난 뒤(afterEvaluate) 35 미만이면 36으로 끌어올린다.
    // evaluationDependsOn 보다 먼저 afterEvaluate 를 등록해야 한다(평가 완료 후 등록 불가).
    afterEvaluate {
        val libExt = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (libExt != null && libExt.compileSdk != null && libExt.compileSdk!! < 36) {
            libExt.compileSdk = 36
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
