plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.shivaduke.kotlinslang.sample"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.shivaduke.kotlinslang.sample"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            // Shrink and obfuscate like a real consumer would. This is what exercises the
            // consumer ProGuard rules shipped in the kotlinslang AAR.
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
            testProguardFiles("proguard-test-rules.pro")
        }
    }

    // Run instrumentation tests against the minified release build so that R8 regressions
    // (see issue #5) are caught by `./gradlew :sample:connectedAndroidTest`.
    testBuildType = "release"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(project(":kotlinslang"))
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
