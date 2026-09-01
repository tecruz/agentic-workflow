plugins {
    alias(libs.plugins.kotlin.jvm)
}

group = "com.example.shared"
version = "1.0"

repositories {
    mavenCentral()
}

dependencies {
    implementation(libs.kotlin.stdlib)
}