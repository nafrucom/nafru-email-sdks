plugins {
    `java-library`
    `maven-publish`
    signing
}

repositories { mavenCentral() }

java {
    withSourcesJar()
    withJavadocJar()
}

tasks.withType<JavaCompile>().configureEach {
    options.release = 17
    options.encoding = "UTF-8"
}

tasks.withType<Javadoc>().configureEach {
    options.encoding = "UTF-8"
    (options as StandardJavadocDocletOptions).addStringOption("Xdoclint:none", "-quiet")
}

dependencies {
    api("com.fasterxml.jackson.core:jackson-databind:2.22.4")
    testImplementation(platform("org.junit:junit-bom:5.11.4"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test { useJUnitPlatform() }

fun secret(property: String, env: String): String? =
    findProperty(property) as String? ?: System.getenv(env)

publishing {
    publications {
        create<MavenPublication>("maven") {
            artifactId = "nafru-email"
            from(components["java"])
            pom {
                name = "Nafru Email Java SDK"
                description = "Official Nafru Email Java SDK: send transactional and marketing email from Java with a Resend-compatible email API, plus contacts, broadcasts, templates, custom events, webhook verification and Connect with Nafru (OAuth)."
                url = "https://github.com/nafrucom/nafru-email"
                licenses {
                    license {
                        name = "MIT License"
                        url = "https://opensource.org/licenses/MIT"
                    }
                }
                developers {
                    developer {
                        id = "nafru"
                        name = "Nafru"
                        url = "https://github.com/nafrucom"
                    }
                }
                scm {
                    url = "https://github.com/nafrucom/nafru-email-sdks"
                    connection = "scm:git:https://github.com/nafrucom/nafru-email-sdks.git"
                    developerConnection = "scm:git:ssh://git@github.com/nafrucom/nafru-email-sdks.git"
                }
            }
        }
    }
    repositories {
        // Central Portal'ın OSSRH uyumlu hazırlama ucu; yüklemeden sonra depo Portal'a ayrıca aktarılır (README).
        maven {
            name = "central"
            url = uri("https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/")
            credentials {
                username = secret("centralUsername", "CENTRAL_USERNAME")
                password = secret("centralPassword", "CENTRAL_PASSWORD")
            }
        }
    }
}

signing {
    val key = secret("signingKey", "SIGNING_KEY")
    // Anahtar yoksa yerel derleme/publishToMavenLocal imzasız çalışır; Central imzasız paketi reddeder.
    if (key != null) {
        useInMemoryPgpKeys(key, secret("signingPassword", "SIGNING_PASSWORD"))
        sign(publishing.publications["maven"])
    }
}
