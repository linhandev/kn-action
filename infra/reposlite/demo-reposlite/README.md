# Demo: test Reposlite remote

Minimal project to verify resolution through `http://localhost:8080/releases`.

## Prerequisites

- JDK 17+ (Gradle 8.5+). If the default is Java 8: `export JAVA_HOME=/usr/lib/jvm/java-21-openjdk`
- Start Reposlite from this directory:

   ```bash
   cd infra/reposlite
   ./start.sh
   ```

2. Ensure the server is listening on `localhost:8080`.

## Run

```bash
cd demo-reposlite
./gradlew dependencies
./gradlew runDemo
```

If the remote works, `gson` is resolved from Reposlite and the demo prints `Reposlite demo OK: "hello"`.
