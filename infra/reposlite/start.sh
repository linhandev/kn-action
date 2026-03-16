#!/usr/bin/env bash
# Reposilite runs with working directory = workspace/
# so reposilite.db, repositories/, logs/, etc. all live under workspace/
set -e
cd "$(dirname "$0")"

if [[ -z "${JAVA:-}" ]]; then
  JAVA=/usr/lib/jvm/java-21-openjdk/bin/java
  if [[ ! -x "$JAVA" ]]; then
    JAVA=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java
  fi
fi
WORKSPACE="$(pwd)/workspace"
JAR="reposilite.jar"

mkdir -p "$WORKSPACE/logs"
cd "$WORKSPACE"

if ! "$JAVA" -version &>/dev/null; then
  echo "Java not found: $JAVA" >&2
  echo "Configure Java: set JAVA to your java binary, or install e.g. openjdk-21." >&2
  echo "  export JAVA=/path/to/java" >&2
  exit 1
fi

if [[ ! -f "$JAR" ]]; then
  echo "Downloading Reposilite 3.5.28..." >&2
  curl -f -L -o "$JAR" \
    "https://maven.reposilite.com/releases/com/reposilite/reposilite/3.5.28/reposilite-3.5.28-all.jar"
fi

exec "$JAVA" -jar "$JAR" \
  --shared-configuration="$(dirname "$0")/configuration.shared.json" \
  --working-directory="$WORKSPACE"
