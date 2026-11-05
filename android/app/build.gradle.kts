plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mycloud.my_cloud"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.iana.taxi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "app"
    productFlavors {
        create("passenger") {
            dimension = "app"
            applicationIdSuffix = ".passenger"
            resValue("string", "app_name", "Taxi Passenger")
        }
        create("driver") {
            dimension = "app"
            applicationIdSuffix = ".driver"
            resValue("string", "app_name", "Taxi Driver")
        }
    }

    buildTypes {
        release {
            // Для тестовой установки APK подписывается debug-ключом CI.
            // Для публикации в Google Play настройте собственную подпись.
            signingConfig = signingConfigs.getByName("debug")
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
