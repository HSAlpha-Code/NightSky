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
// flutter_rotation_sensor 0.2.0 hardcodes compileSdk 35, but its dependency
// native_device_orientation requires 36. Must be registered before evaluationDependsOn below.
subprojects {
    if (name == "flutter_rotation_sensor") {
        afterEvaluate {
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
