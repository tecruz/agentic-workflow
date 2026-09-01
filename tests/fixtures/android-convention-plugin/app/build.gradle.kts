plugins {
    id("com.example.android.lib")
}

android {
    namespace = "com.example.app"
    compileSdk = 34
    defaultConfig {
        minSdk = 24
        targetSdk = 34
    }
}