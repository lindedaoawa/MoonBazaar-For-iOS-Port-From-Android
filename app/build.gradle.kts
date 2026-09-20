plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "top.witzzz.moonbazaar"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "top.witzzz.moonbazaar"
        minSdk = 29
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
    }
}

// ---------------------------------------------------------------------------
// Android Studio Gradle Sync 兼容用占位任务
//
// AGP 9 使用「内置 Kotlin」编译 Kotlin：不能再应用 org.jetbrains.kotlin.android
// （会与内置注册的 kotlin 扩展冲突：Cannot add extension with name 'kotlin'），
// 而内置 Kotlin 只在根项目注册 prepareKotlinBuildScriptModel，
// 于是 Android Studio 在 :app 上请求该任务时报：
//   Task 'prepareKotlinBuildScriptModel' not found in project ':app'
//
// 这里补一个空实现，让 IDE 的 Sync 能正常完成。
// ---------------------------------------------------------------------------
tasks.register("prepareKotlinBuildScriptModel") {
    group = "build setup"
    description = "Android Studio Gradle Sync 兼容占位任务（AGP 9 内置 Kotlin 不注册该任务）"
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.okhttp)
    implementation(libs.androidx.browser)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}