package com.example

import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.*

class AndroidLibConventionPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        with(project) {
            pluginManager.apply("com.android.library")
            pluginManager.apply("org.jetbrains.kotlin.android")
            
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                namespace = "com.example.lib"
                compileSdk = 34
                defaultConfig {
                    minSdk = 24
                    targetSdk = 34
                }
            }
            
            dependencies {
                add("implementation", "androidx.core:core-ktx:1.12.0")
            }
        }
    }
}