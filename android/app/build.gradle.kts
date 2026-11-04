plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.lyra.lyra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.lyra.lyra"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 测试包签名：固定的测试 keystore（提交在仓库里，口令公开，只用于内部测试包）。
    // 每次 CI 打包签名一致，新包可以直接覆盖安装，不用卸载、不丢登录态。
    // 正式上架前要换成单独保管的发布 keystore（通过 CI secret 注入），不能用这把。
    signingConfigs {
        create("lyraTest") {
            storeFile = file("lyra-test.jks")
            storePassword = "lyratest"
            keyAlias = "lyra-test"
            keyPassword = "lyratest"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("lyraTest")
        }
        release {
            signingConfig = signingConfigs.getByName("lyraTest")
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
