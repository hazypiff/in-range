allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// After each subproject is evaluated, force Java/Kotlin 17 so legacy
// plugins (flutter_ble_peripheral etc.) cannot drift to a different target.
subprojects {
    afterEvaluate {
        // Java compile tasks
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        // Kotlin compile tasks (may not exist if no kotlin plugin)
        try {
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        } catch (_: Exception) {
            // Plugin not on classpath for this subproject — fine.
        }
    }
}

// Keep evaluationDependsOn for Flutter template compatibility, but note it
// can slow configuration. Leave as-is for now.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
