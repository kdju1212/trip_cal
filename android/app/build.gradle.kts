import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val sideBySide = providers.gradleProperty("sideBySide").orNull == "true"
val signingProperties = Properties()
val signingFile = rootProject.file("key.properties")
if (signingFile.exists()) signingFile.inputStream().use { signingProperties.load(it) }
// Never produce a Play Store release bundle with the debug key.
if (!signingFile.exists() && gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) && it.contains("release", ignoreCase = true) }) {
    throw GradleException("A release signing key is required for a release app bundle. Configure android/key.properties.")
}

// The first Play release ships without ads, and docs/PRIVACY.md says no data reaches our
// servers. A Play bundle that carries the ad server settings would contradict that, so it is
// refused unless ads are deliberately enabled (-PallowAds=true or ORG_GRADLE_PROJECT_allowAds=true)
// after the privacy policy is updated. Test APKs are not affected.
// Flutter passes --dart-define values as a comma-separated list of base64 "KEY=VALUE" entries.
val allowAds = providers.gradleProperty("allowAds").orNull == "true"
val adServerDefines = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(",")
    .filter { it.isNotBlank() }
    .map { entry -> runCatching { String(java.util.Base64.getDecoder().decode(entry), Charsets.UTF_8) }.getOrDefault("") }
    .filter { define -> listOf("SUPABASE_URL=", "SUPABASE_ANON_KEY=").any { define.startsWith(it) && define.length > it.length } }
if (!allowAds && adServerDefines.isNotEmpty() && gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) && it.contains("release", ignoreCase = true) }) {
    throw GradleException(
        "Release app bundles must not include SUPABASE_URL or SUPABASE_ANON_KEY while ads are off " +
            "(see docs/RELEASE.md). Remove those --dart-define values, or set -PallowAds=true after updating docs/PRIVACY.md."
    )
}

// Code shrinking (R8) removed the WorkManager database constructor and made release builds
// crash at startup, so it must stay off. Only scripts/check_release_guards.sh sets this
// property, to prove that the guard at the end of this file still rejects shrinking.
val releaseGuardSelfTest = providers.gradleProperty("releaseGuardSelfTest").orNull == "true"


android {
    namespace = "com.tripcal.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tripcal.app"
        if (sideBySide) {
            applicationIdSuffix = ".preview24"
        }
        manifestPlaceholders["appLabel"] = if (sideBySide) "여행 준비 도우미 (수정 24)" else "여행 준비 도우미"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        release {
            // WorkManager / Room initialization must remain intact in release builds.
            isMinifyEnabled = releaseGuardSelfTest
            isShrinkResources = false
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName(if (signingFile.exists()) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Whatever turns shrinking back on (a missing --no-shrink, the Flutter plugin, or an edit above),
// stop before R8 runs instead of producing an APK or bundle that crashes at startup.
gradle.taskGraph.whenReady {
    val shrinkTasks = allTasks
        .filter { it.project.path == project.path }
        .map { it.name }
        .filter { Regex("^(minify|shrink)\\w*Release\\w*$", RegexOption.IGNORE_CASE).matches(it) }
    if (shrinkTasks.isNotEmpty()) {
        throw GradleException(
            "Code shrinking must stay off for release builds: it removes the WorkManager database " +
                "constructor and the app crashes at startup. Build with --no-shrink. Tasks: ${shrinkTasks.joinToString()}"
        )
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
