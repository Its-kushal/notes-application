import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val requestedTasks = gradle.startParameter.taskNames
val isMaintenanceOnly = requestedTasks.isNotEmpty() && requestedTasks.all {
    it.endsWith("clean", ignoreCase = true) ||
        it.endsWith("tasks", ignoreCase = true) ||
        it.endsWith("help", ignoreCase = true)
}

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    val requiredKeys = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
    val missingKeys = requiredKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (!isMaintenanceOnly && missingKeys.isNotEmpty()) {
        throw GradleException(
            "Invalid android/key.properties: missing required keys ${missingKeys.joinToString(", ")}. " +
                "See android/key.properties.example for required fields."
        )
    }
    val storeFilePath = keystoreProperties.getProperty("storeFile")
    if (!isMaintenanceOnly && !storeFilePath.isNullOrBlank() && !file(storeFilePath).exists()) {
        throw GradleException(
            "Release keystore not found at storeFile path in android/key.properties. " +
                "Verify the path points to your external .jks/.keystore file."
        )
    }
} else if (!isMaintenanceOnly) {
    throw GradleException(
        "Missing android/key.properties. Copy android/key.properties.example to android/key.properties " +
            "and configure your external LeafLock release keystore before building debug or release APKs."
    )
}

android {
    namespace = "com.leaflock.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.leaflock.app"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        getByName("release") {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
