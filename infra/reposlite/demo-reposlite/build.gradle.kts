plugins {
    java
}

group = "demo.reposlite"
version = "1.0"

repositories {
    maven {
        url = uri("http://localhost:8080/releases")
        isAllowInsecureProtocol = true
    }
    mavenCentral()
}

dependencies {
    implementation("com.google.code.gson:gson:2.11.0")
}

tasks.register<JavaExec>("runDemo") {
    group = "application"
    mainClass.set("demo.Main")
    classpath = sourceSets["main"].runtimeClasspath
}
