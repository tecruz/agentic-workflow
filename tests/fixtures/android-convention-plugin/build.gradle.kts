plugins {
    id("com.example.android.lib") apply false
}

subprojects {
    repositories {
        mavenCentral()
        google()
    }
}