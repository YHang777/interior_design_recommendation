plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // kotlin-android removed: Built-in Kotlin (android.builtInKotlin=true)
    // compiles MainActivity.kt now — see Flutter's migrate-to-built-in-kotlin
    // app-developer guide. The top-level kotlin {} block below stays.
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.interior_design_recommendation"
    compileSdk = 36
    // Override Flutter's default NDK with plugin-required version
    ndkVersion = "28.2.13676358"

    compileOptions {
        // flutter_stripe (Payments API) requires core library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.interior_design_recommendation"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28 // Firebase Auth requires 23+, ARCore (ar_flutter_plugin_2 / SceneView) requires 28+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// sceneview → fuel pulls the deprecated kotlin-android-extensions-runtime,
// whose kotlinx.android.parcel.* classes duplicate kotlin-parcelize-runtime
// (flutter_stripe). The parcelize artifact is the drop-in replacement.
configurations.all {
    exclude(group = "org.jetbrains.kotlin", module = "kotlin-android-extensions-runtime")
}

flutter {
    source = "../.."
}
