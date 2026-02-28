pluginManagement {
    // Flutter 3.29+ uses a local Gradle plugin: dev.flutter.flutter-plugin-loader
    // It must be resolved from the Flutter SDK via includeBuild.
    val flutterSdkPath = System.getenv("FLUTTER_ROOT") ?: "D:\\tools\\flutter"
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // mirrors (optional)
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

include(":app")
