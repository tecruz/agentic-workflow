plugins {
    alias(libs.plugins.android.application)
    id("android.library.convention")
}

android {
    namespace = "com.example.app"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.app"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation(libs.androidx.core)
}