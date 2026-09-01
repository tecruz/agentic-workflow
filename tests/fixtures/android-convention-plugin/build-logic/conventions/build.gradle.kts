plugins {
    `kotlin-dsl`
}

repositories {
    gradlePluginPortal()
    google()
}

dependencies {
    implementation("com.android.tools.build:gradle:8.5.0")
    implementation("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.23")
}

gradlePlugin {
    plugins {
        create("android-lib") {
            id = "com.example.android.lib"
            implementationClass = "com.example.AndroidLibConventionPlugin"
        }
    }
}