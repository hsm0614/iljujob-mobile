pluginManagement {
    val properties = java.util.Properties()
    file("local.properties").inputStream().use { properties.load(it) }
    val flutterSdkPath = properties.getProperty("flutter.sdk")
    require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // (선택) 플러그인 해상도도 여기서만 관리하고 싶다면 아래 두 줄을 넣어도 무방
        // maven(url = "https://storage.googleapis.com/download.flutter.io")
        // maven(url = "https://devrepo.kakao.com/nexus/repository/kakaomap-releases/")
    }

    plugins {
        id("com.android.application") version "8.7.0"
        id("org.jetbrains.kotlin.android") version "2.0.21"
        id("com.google.gms.google-services") version "4.4.2"
        // Crashlytics 플러그인 쓰면 여기에 버전도 명시
        // id("com.google.firebase.crashlytics") version "3.0.2"
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    // id("com.google.firebase.crashlytics") apply false
}

/**
 * 프로젝트(모듈) 쪽에 저장소를 추가해도 빌드가 터지지 않도록 완화.
 * Flutter Gradle 플러그인이 내부적으로 maven 저장소를 추가할 수 있어 FAIL_ON_PROJECT_REPOS는 충돌을 냄.
 */
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        // Flutter 엔진/바이너리
        maven(url = "https://storage.googleapis.com/download.flutter.io")
        // Kakao Maps SDK
        maven(url = "https://devrepo.kakao.com/nexus/repository/kakaomap-releases/")
    }
}

include(":app")