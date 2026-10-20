// Binah for Android, native: Kotlin and Jetpack Compose over Binah's JSON API (docs/API.md), not a
// WebView. It runs beside the WebView app in android/ until it covers everything, then replaces it.
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "xyz.tiresia.binah.app"
    compileSdk = 36

    defaultConfig {
        // the WebView app's id, signed with the same key: this installs as an update over it
        applicationId = "xyz.tiresia.binah"
        minSdk = 31
        targetSdk = 36
        versionCode = 2
        versionName = "0.2.0"
        resValue("string", "app_name", "Binah")
        resValue("string", "share_label", "Train on this")
        resValue("string", "widget_label", "Binah: today\\'s edition")
    }

    // The signing key's properties: android/keystore.properties (never in git), or the file
    // -PsigningProperties names (release.sh). storeFile is found beside the properties file.
    val secrets = if (project.hasProperty("signingProperties")) file(project.property("signingProperties") as String)
                  else rootProject.file("keystore.properties")
    signingConfigs {
        create("release") {
            if (secrets.exists()) {
                val p = Properties().apply { secrets.inputStream().use { load(it) } }
                val store = File(p.getProperty("storeFile", "android.keystore"))
                storeFile = if (store.isAbsolute) store else File(secrets.parentFile, store.path)
                storePassword = p.getProperty("storePassword")
                keyAlias = p.getProperty("keyAlias", "binah")
                keyPassword = p.getProperty("keyPassword", p.getProperty("storePassword"))
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (secrets.exists()) signingConfig = signingConfigs.getByName("release")
        }
        debug {
            applicationIdSuffix = ".debug"
            resValue("string", "app_name", "Binah dev")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    lint { checkReleaseBuilds = false }
}

kotlin { jvmToolchain(17) }

dependencies {
    val bom = platform("androidx.compose:compose-bom:2026.06.01")
    implementation(bom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.navigation:navigation-compose:2.9.8")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
