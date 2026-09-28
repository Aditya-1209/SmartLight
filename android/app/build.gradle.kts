plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aditya.smartlight.smart_light"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aditya.smartlight.smart_light"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// Release HTTP is limited to a build-time private IPv4 address. The generated
// resource has variant priority over the default deny-all policy.
abstract class GenerateLocalNetworkPolicy : DefaultTask() {
    @get:Input abstract val tapoAddress: org.gradle.api.provider.Property<String>
    @get:OutputDirectory abstract val outputDirectory: org.gradle.api.file.DirectoryProperty
    @TaskAction fun generate() {
        val ip = tapoAddress.get()
        val parts = ip.split(".").mapNotNull { it.toIntOrNull() }
        val valid = Regex("[0-9]{1,3}(\\.[0-9]{1,3}){3}").matches(ip) && parts.size == 4 && parts.all { it in 0..255 } &&
            (parts[0] == 10 || (parts[0] == 172 && parts[1] in 16..31) ||
                (parts[0] == 192 && parts[1] == 168) || (parts[0] == 169 && parts[1] == 254))
        require(ip.isEmpty() || valid) { "SMARTLIGHT_TAPO_IP must be a private IPv4 literal" }
        val rule = if (ip.isEmpty()) "" else
            "<domain-config cleartextTrafficPermitted=\"true\"><domain includeSubdomains=\"false\">$ip</domain></domain-config>"
        val output = outputDirectory.get().file("xml/network_security_config.xml").asFile
        output.parentFile.mkdirs()
        output.writeText("<?xml version=\"1.0\" encoding=\"utf-8\"?><network-security-config><base-config cleartextTrafficPermitted=\"false\" />$rule</network-security-config>")
    }
}
val generateLocalNetworkPolicy = tasks.register<GenerateLocalNetworkPolicy>("generateLocalNetworkPolicy") {
    tapoAddress.set(providers.environmentVariable("SMARTLIGHT_TAPO_IP").orElse(""))
    outputDirectory.set(layout.buildDirectory.dir("generated/localNetworkResources"))
}
androidComponents.onVariants(androidComponents.selector().withBuildType("release")) { variant ->
    variant.sources.res?.addGeneratedSourceDirectory(generateLocalNetworkPolicy, GenerateLocalNetworkPolicy::outputDirectory)
}
