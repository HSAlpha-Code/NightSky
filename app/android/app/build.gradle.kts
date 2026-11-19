import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key: android/key.properties + the .jks it points to (both git-ignored).
// Public release builds must never fall back to debug signing.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "com.nightsky.night_sky"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nightsky.night_sky"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml "version: 1.0.0+1" (name+code); bump it for every new APK.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
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

val verifyReleaseReadiness by tasks.registering(Exec::class) {
    group = "verification"
    description = "Block public builds with unresolved legal/privacy release inputs."
    workingDir(rootProject.projectDir.resolve("../.."))
    commandLine("python", "tools/release.py", "check", "--for-build")
    doFirst {
        check(hasReleaseKey) {
            "Release key missing. Configure android/key.properties; debug signing is prohibited."
        }
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach {
            check(!keyProperties.getProperty(it).isNullOrBlank()) { "Release signing field missing: $it" }
        }
        check(rootProject.file(keyProperties.getProperty("storeFile")).isFile) {
            "Configured release keystore does not exist."
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(verifyReleaseReadiness)
}
