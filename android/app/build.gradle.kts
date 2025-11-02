plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.refocus_app"
    compileSdk = 36  // ✅ Updated for latest plugins
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.refocus_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36  // ✅ Match the latest compileSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true  // ✅ Correct Kotlin DSL syntax
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // ✅ Using debug keys temporarily
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Required for desugaring (needed by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
