#!/usr/bin/env bash
# Run Kotlin scripts/build-ohos.sh with the same Reposilite-oriented setup as CI (build-kotlin.yml):
# - Gradle wrapper zip from <REPOSLITE_BASE>/gradle-distributions/ (via rewrite-gradle-wrapper-reposlite.sh)
# - Maven + Gradle artifact repos via maven-proxy.init.gradle + settings.xml mirror → <REPOSLITE_BASE>/releases
# - Isolated HOME, GRADLE_USER_HOME, MAVEN_USER_HOME, KONAN_DATA_DIR (build-ohos.sh cleans $HOME/.m2 — use fake HOME)
# - cache-redirector disabled; CN mirror init script off so resolution stays on the proxy
#
# Usage:
#   REPOSLITE_BASE=http://127.0.0.1:8080 \
#     ./scripts/run-build-ohos-with-reposlite-proxy.sh /path/to/kotlin
#
# Env:
#   REPOSLITE_BASE          default http://127.0.0.1:8080  (no trailing slash)
#   BUILD_OHOS_CACHE_ROOT   default /tmp/build-ohos-reposlite-$UID
#   BUILD_OHOS_CLEAN_CACHE  default 1; set 0 to reuse BUILD_OHOS_CACHE_ROOT
#   JDK_18                  optional; default: macOS /usr/libexec/java_home -v 1.8
set -euo pipefail

KOTLIN_ROOT="$(cd "${1:?path to kotlin repo root}" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KN_ACTION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

REPOSLITE_BASE="${REPOSLITE_BASE:-http://127.0.0.1:8080}"
REPOSLITE_BASE="${REPOSLITE_BASE%/}"
MAVEN_PROXY_URL="${MAVEN_PROXY_URL:-$REPOSLITE_BASE/releases}"
GRADLE_DIST_BASE="${GRADLE_DIST_BASE:-$REPOSLITE_BASE/gradle-distributions}"

BUILD_OHOS_CACHE_ROOT="${BUILD_OHOS_CACHE_ROOT:-/tmp/build-ohos-reposlite-$UID}"
BUILD_OHOS_CLEAN_CACHE="${BUILD_OHOS_CLEAN_CACHE:-1}"

if [[ "$BUILD_OHOS_CLEAN_CACHE" == "1" ]]; then
  rm -rf "$BUILD_OHOS_CACHE_ROOT"
fi

export HOME="$BUILD_OHOS_CACHE_ROOT/fakehome"
mkdir -p "$HOME"

export GRADLE_USER_HOME="$BUILD_OHOS_CACHE_ROOT/gradle"
mkdir -p "$GRADLE_USER_HOME/init.d"
cp "$KN_ACTION_ROOT/scripts/maven-proxy.init.gradle" "$GRADLE_USER_HOME/init.d/"

export MAVEN_USER_HOME="$BUILD_OHOS_CACHE_ROOT/maven"
mkdir -p "$MAVEN_USER_HOME/.m2"
export MAVEN_OPTS="-Duser.home=$MAVEN_USER_HOME"
export MAVEN_PROXY_URL
export KONAN_DATA_DIR="${KONAN_DATA_DIR:-$BUILD_OHOS_CACHE_ROOT/konan}"
mkdir -p "$KONAN_DATA_DIR"

# OH Kotlin versions resolve from build/repo (file) during the build; keep that repo out of the Reposilite mirror.
BUILD_REPO_ABS="$(cd "$KOTLIN_ROOT" && pwd -P)/build/repo"
FILE_BUILD_REPO_URL="file://${BUILD_REPO_ABS}"
LOCAL_BUILD_REPO_ID="kn-action-local-build-repo"

cat > "$MAVEN_USER_HOME/.m2/settings.xml" <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <localRepository>${MAVEN_USER_HOME}/.m2/repository</localRepository>
  <mirrors>
    <mirror>
      <id>maven-proxy</id>
      <mirrorOf>external:*,!${LOCAL_BUILD_REPO_ID}</mirrorOf>
      <url>${MAVEN_PROXY_URL}</url>
    </mirror>
  </mirrors>
  <profiles>
    <profile>
      <id>kn-action-kotlin-build-repo</id>
      <activation><activeByDefault>true</activeByDefault></activation>
      <repositories>
        <repository>
          <id>${LOCAL_BUILD_REPO_ID}</id>
          <url>${FILE_BUILD_REPO_URL}</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </repository>
      </repositories>
      <pluginRepositories>
        <repository>
          <id>${LOCAL_BUILD_REPO_ID}</id>
          <url>${FILE_BUILD_REPO_URL}</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </repository>
      </pluginRepositories>
    </profile>
  </profiles>
</settings>
EOF

export ORG_GRADLE_PROJECT_cacheRedirectorEnabled=false
export USE_CN_MIRROR=false

if [[ -z "${JDK_18:-}" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    export JDK_18="$(/usr/libexec/java_home -v 1.8 2>/dev/null || true)"
  fi
fi
if [[ -z "${JDK_18:-}" ]]; then
  echo "ERROR: JDK_8 is required. Install JDK 8 and export JDK_18=<path>." >&2
  exit 1
fi

echo "Reposilite: MAVEN_PROXY_URL=$MAVEN_PROXY_URL"
echo "Reposilite: Gradle distributions base=$GRADLE_DIST_BASE"
echo "Isolated: HOME=$HOME GRADLE_USER_HOME=$GRADLE_USER_HOME MAVEN_USER_HOME=$MAVEN_USER_HOME KONAN_DATA_DIR=$KONAN_DATA_DIR"

bash "$SCRIPT_DIR/rewrite-gradle-wrapper-reposlite.sh" "$KOTLIN_ROOT" "$GRADLE_DIST_BASE"

export GRADLE_OPTS="${GRADLE_OPTS:--Dorg.gradle.internal.repository.max.tentatives=16 -Dorg.gradle.internal.repository.initial.backoff=5000}"

cd "$KOTLIN_ROOT"
bash scripts/build-ohos.sh
./gradlew --stop 2>/dev/null || true
