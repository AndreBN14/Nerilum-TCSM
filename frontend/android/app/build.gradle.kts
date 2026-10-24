import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de producción: se lee únicamente desde android/key.properties (ignorado por Git).
// Sin esa configuración válida, cualquier tarea de release falla de forma explícita
// en cuanto se intenta ejecutar; nunca hay un fallback silencioso a la clave debug.
// Consulta frontend/RELEASE.md para configurarla.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val releaseStoreFile: File? = if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    val configuredPath = keystoreProperties.getProperty("storeFile")
    if (configuredPath.isNullOrBlank()) {
        null
    } else {
        val candidate = File(configuredPath)
        if (candidate.isAbsolute) candidate else file(configuredPath)
    }
} else {
    null
}
val hasReleaseSigning = releaseStoreFile?.isFile == true &&
    !keystoreProperties.getProperty("storePassword").isNullOrBlank() &&
    !keystoreProperties.getProperty("keyAlias").isNullOrBlank()

android {
    namespace = "io.github.andrebn14.nerilum"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identificador definitivo de producción (ver frontend/RELEASE.md).
        applicationId = "io.github.andrebn14.nerilum"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        // En publicaciones oficiales el workflow inyecta --build-name/--build-number
        // derivados de la etiqueta; ver frontend/RELEASE.md.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                // Si keyPassword no se define, se usa la contraseña del keystore.
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Solo la clave de producción; sin ella la configuración queda en null
            // y el bloque inferior impide ejecutar cualquier tarea de release.
            // Bajo ninguna circunstancia se firma con la clave debug.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
        }
    }
}

if (!hasReleaseSigning) {
    tasks.configureEach {
        if (name.contains("Release", ignoreCase = true)) {
            doFirst {
                throw GradleException(
                    "Falta la firma de producción: no existe android/key.properties con un " +
                        "keystore válido, o el archivo referenciado no está. Ninguna tarea de " +
                        "release puede ejecutarse sin firma. Consulta frontend/RELEASE.md."
                )
            }
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
