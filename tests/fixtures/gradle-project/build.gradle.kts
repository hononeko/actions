// Prints the JVM the build runs on, so CI can check gradle-setup installed the pinned JDK.
tasks.register("printJavaVersion") {
    doLast { println(System.getProperty("java.version")) }
}
