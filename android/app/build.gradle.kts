import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.inrange.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.inrange.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Taken from Flutter (pubspec, or --build-name/--build-code) rather than
        // hardcoded: build-install-s9.sh stamps the commit into --build-name so
        // walk_capture.sh can verify a phone is on the frozen build before a
        // calibration walk. Hardcoding here silently discards that stamp.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
        }
    }

    // Align Java + Kotlin to 17 (matches system JDK and plugin defaults).
    // Previous mismatch was Java 11 vs Kotlin 17 → compileDebugKotlin failed.
    compileOptions {
        // Required by flutter_local_notifications (java.time on older APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    // Release signing must be supplied by CI/Play. Never ship the debug key.
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // JVM unit tests, src/test/kotlin. Plain JUnit and nothing else on purpose:
    // AdvertParser.kt is a pure Kotlin `object` over ByteArray with no Android
    // imports, so its AD-walk and offset arithmetic — the load-bearing part, the
    // part a wrong answer makes us silently blind to backgrounded iPhones —
    // needs no Robolectric, no android.jar shadow, no emulator and no attached
    // handset. That is the whole reason the parser was written that way.
    // Anything that needs a Context or a BluetoothLeScanner belongs in
    // androidTest, not here; do not reach for Robolectric to widen this.
    //
    // Run: ./gradlew :app:testDebugUnitTest
    // NOT in CI yet — .github/workflows/ci.yml runs `flutter analyze` and
    // `flutter test` only and never invokes Gradle, so this task has to be run
    // by hand until an Android job exists. Adding one is the cheap follow-up.
    testImplementation("junit:junit:4.13.2")
}

// Force every KotlinCompile task (app + transitive plugins) onto JVM 17.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}
