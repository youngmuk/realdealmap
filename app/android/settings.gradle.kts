pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP를 8.13.2에 고정한다. **임시 조치다.**
    //
    // maplibre_gl 0.27.0의 안드로이드 빌드 스크립트가 AGP 9에서 깨진다
    // (`Could not find method kotlin()`). 패키지가 AGP 9를 지원하면 되돌린다.
    // T1.3 스파이크에서 같은 벽에 부딪혀 확인한 값이다.
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
