plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val photoNamerTargetAbi =
    providers.gradleProperty("photoNamerTargetAbi").orNull?.trim()?.takeIf { it.isNotEmpty() }
val photoNamerAllAbis = listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
val photoNamerExcludedAbiPatterns =
    photoNamerTargetAbi?.let { targetAbi ->
        photoNamerAllAbis
            .filter { abi -> abi != targetAbi }
            .map { abi -> "lib/$abi/**" }
    } ?: emptyList()

android {
    namespace = "com.example.photo_namer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.photo_namer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        if (photoNamerTargetAbi != null) {
            ndk {
                abiFilters.add(photoNamerTargetAbi)
            }
        }
    }

    packaging {
        jniLibs {
            excludes += photoNamerExcludedAbiPatterns
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("com.google.guava:guava:33.4.8-android")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.0")
}

flutter {
    source = "../.."
}
