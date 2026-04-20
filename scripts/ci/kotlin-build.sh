#!/usr/bin/env bash
# GitLab CI port of .github/workflows/build-kotlin.yml (matrix: linux-x64, macos-arm64, macos-x64, windows-x64).
# Requires: runner has GitCode SSH for kotlin clone; JDK 8/11/17/21 per platform (see resolve_java_*).
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"

PLATFORM="${1:?usage: kotlin-build.sh linux-x64|macos-arm64|macos-x64|windows-x64}"

cd "$CI_PROJECT_DIR"

case "$PLATFORM" in
  linux-x64) export RUNNER_OS=Linux; export RUNNER_ARCH=X64 ;;
  macos-arm64) export RUNNER_OS=macOS; export RUNNER_ARCH=ARM64 ;;
  macos-x64) export RUNNER_OS=macOS; export RUNNER_ARCH=X64 ;;
  windows-x64) export RUNNER_OS=Windows; export RUNNER_ARCH=X64 ;;
  *) echo "Unknown platform: $PLATFORM" >&2; exit 1 ;;
esac

# --- defaults (match build-kotlin.yml env) ---
export DEFAULT_KOTLIN_BRANCH="${DEFAULT_KOTLIN_BRANCH:-develop-2.2.21-OH}"
export DEFAULT_CLEAN_BUILD="${DEFAULT_CLEAN_BUILD:-false}"
export DEFAULT_MAVEN_PROXY_URL="${DEFAULT_MAVEN_PROXY_URL:-http://192.168.3.5:8080/releases}"
export DEFAULT_GRADLE_DISTRIBUTIONS_URL="${DEFAULT_GRADLE_DISTRIBUTIONS_URL:-http://192.168.3.5:8080/distributions}"
export REPO_URL="${REPO_URL:-git@gitcode.com:CPF-KMP-CMP/kotlin.git}"
export WORKSPACE_DIR="${WORKSPACE_DIR:-ci-workspace}"
export LOCAL_REFERENCE_DIR="${LOCAL_REFERENCE_DIR:-$HOME/git/ci/}"
export PERSISTED_CACHE_ROOT="${PERSISTED_CACHE_ROOT:-$HOME/gitlab-runner/cache}"
export ARTIFACT_LOCAL_PATH="${ARTIFACT_LOCAL_PATH:-$HOME/runner/artifact}"

export BRANCH="${KOTLIN_BRANCH:-$DEFAULT_KOTLIN_BRANCH}"
export COMMIT="${KOTLIN_COMMIT:-}"
export PR_NUMBER="${KOTLIN_PR_NUMBER:-}"

RUNNER_TEMP="${RUNNER_TEMP:-${CI_PROJECT_DIR}/.ci-tmp/runner-temp}"
mkdir -p "$RUNNER_TEMP"
export RUNNER_TEMP

PERSISTED_CACHE_ROOT="${PERSISTED_CACHE_ROOT/#\~/$HOME}"
CLEAN_CACHE_ROOT="${RUNNER_TEMP}/clean-cache"
CLEAN_BUILD="${KOTLIN_CLEAN_BUILD:-$DEFAULT_CLEAN_BUILD}"
if [ "${CI_PIPELINE_SOURCE:-}" = "schedule" ]; then
  CLEAN_BUILD="true"
fi
case "$CLEAN_BUILD" in
  true|1|yes) CLEAN_BUILD="true" ;;
  *) CLEAN_BUILD="false" ;;
esac

if [ "$CLEAN_BUILD" = "true" ]; then
  CI_CACHE_ROOT="${CLEAN_CACHE_ROOT}/"
else
  CI_CACHE_ROOT="${PERSISTED_CACHE_ROOT}/"
fi

GRADLE_USER_HOME="${CI_CACHE_ROOT}gradle_user_home"
KONAN_DATA_DIR="${CI_CACHE_ROOT}/konan_data"
MAVEN_USER_HOME="${CI_CACHE_ROOT}maven_user_home"
MAVEN_LOCAL_REPO="${MAVEN_USER_HOME}/.m2/repository"
ARTIFACT_LOCAL_PATH="${ARTIFACT_LOCAL_PATH/#\~/$HOME}"

# --- Windows: Git for Windows OpenSSH (AGENTS.md) ---
if [ "$RUNNER_OS" = "Windows" ]; then
  if [ -f "$HOME/.ssh/id_ed25519" ] && [ -f "$HOME/.ssh/known_hosts" ]; then
    idf="$(cygpath -m "$HOME/.ssh/id_ed25519" 2>/dev/null || echo "$HOME/.ssh/id_ed25519")"
    khf="$(cygpath -m "$HOME/.ssh/known_hosts" 2>/dev/null || echo "$HOME/.ssh/known_hosts")"
    export GIT_SSH_COMMAND="ssh -i ${idf} -o IdentitiesOnly=yes -o UserKnownHostsFile=${khf} -o StrictHostKeyChecking=yes"
  fi
fi

# --- macOS: Xcode tool presence (ARM build-ohos expectations) ---
if [ "$RUNNER_OS" = "macOS" ]; then
  /usr/bin/xcrun -f bitcode-build-tool >/dev/null 2>&1 || true
fi

# --- Maven proxy (optional) ---
USE_PROXY="${KOTLIN_USE_MAVEN_PROXY:-true}"
case "$USE_PROXY" in
  false|0|no) PROXY_URL="" ;;
  *) PROXY_URL="$DEFAULT_MAVEN_PROXY_URL" ;;
esac

if [ -n "$PROXY_URL" ]; then
  HTTP_CODE=$(curl -so /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 "$PROXY_URL" || true)
  if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
    echo "Maven proxy unreachable; continuing without PROXY_URL"
    PROXY_URL=""
  fi
fi

export NODEJS_DIST_MIRROR="${NODEJS_DIST_MIRROR:-https://npmmirror.com/mirrors/node}"

mkdir -p "$GRADLE_USER_HOME" "$KONAN_DATA_DIR" "$MAVEN_USER_HOME/.m2" "$ARTIFACT_LOCAL_PATH"

mkdir -p "${GRADLE_USER_HOME}/init.d"
cp "$CI_PROJECT_DIR/scripts/proxy.init.gradle" "${GRADLE_USER_HOME}/init.d/"

if [ "$CLEAN_BUILD" = "true" ]; then
  echo "Clean build: wiping Konan and Maven user home under cache root"
  rm -rf "$KONAN_DATA_DIR"
  mkdir -p "$KONAN_DATA_DIR"
  rm -rf "$MAVEN_USER_HOME"
  mkdir -p "$MAVEN_USER_HOME/.m2"
fi

# --- prepare-repo (clone kotlin) ---
export REPO_URL
export BRANCH
export COMMIT
export PR_NUMBER
export WORKSPACE_DIR
export LOCAL_REFERENCE_DIR
# shellcheck source=/dev/null
source "$CI_PROJECT_DIR/.github/actions/prepare-repo/prepare-repo.sh"
cd "$CI_PROJECT_DIR"

KOTLIN_ROOT="${CI_PROJECT_DIR}/${WORKSPACE_DIR}"
KOTLIN_SHA="$(git -C "$KOTLIN_ROOT" rev-parse HEAD)"

# --- patch ---
PATCH="$CI_PROJECT_DIR/patches/kotlin-js-tests-npmSetRegistry.patch"
cd "$KOTLIN_ROOT"
if patch -p1 <"$PATCH"; then
  echo "Applied kotlin-js-tests-npmSetRegistry patch"
elif grep -q 'if (cacheRedirectorEnabled)' js/js.tests/build.gradle.kts 2>/dev/null; then
  echo "kotlin-js-tests guard already present; skipping patch"
else
  echo "ERROR: patch failed and js/js.tests/build.gradle.kts lacks expected guard" >&2
  exit 1
fi
cd "$CI_PROJECT_DIR"

# --- Java toolchains (match GHA setup-java order: default `java` = last installed) ---
# CI variables JAVA_HOME, JDK_18, JAVA_HOME_8, JAVA_HOME_11, JAVA_HOME_17, JAVA_HOME_21 override auto-detect.
if [ -z "${JDK_18:-}" ] && [ -n "${JAVA_HOME_8:-}" ]; then
  export JDK_18="$JAVA_HOME_8"
fi

if [ "$RUNNER_OS" = "macOS" ] && [ -x /usr/libexec/java_home ]; then
  export JDK_18="${JDK_18:-$(/usr/libexec/java_home -v 1.8 2>/dev/null || true)}"
  if [ "$RUNNER_ARCH" = "ARM64" ]; then
    export JAVA_HOME="${JAVA_HOME_17:-$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)}"
  else
    export JAVA_HOME="${JAVA_HOME_11:-$(/usr/libexec/java_home -v 11 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)}"
  fi
elif [ "$RUNNER_OS" = "Linux" ]; then
  for d in /usr/lib/jvm/java-8-openjdk-amd64 /usr/lib/jvm/java-1.8.0-openjdk-amd64 \
           /usr/lib/jvm/java-8-openjdk /usr/lib/jvm/zulu-8; do
    [ -d "$d" ] && export JDK_18="${JDK_18:-$d}" && break
  done
  for d in /usr/lib/jvm/java-21-openjdk-amd64 /usr/lib/jvm/java-21-openjdk \
           /usr/lib/jvm/temurin-21-amd64 /usr/lib/jvm/java-11-openjdk; do
    if [ -d "$d" ]; then
      export JAVA_HOME="${JAVA_HOME_21:-$d}"
      break
    fi
  done
  if [ -n "${JAVA_HOME_21:-}" ]; then
    export JAVA_HOME="$JAVA_HOME_21"
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
  if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
    export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  fi
elif [ "$RUNNER_OS" = "Windows" ]; then
  shopt -s nullglob
  for d in /c/Program\ Files/Eclipse\ Adoptium/jdk-8* \
           /c/Program\ Files/Eclipse\ Adoptium/jdk8u* \
           /c/Program\ Files/BellSoft/LibericaJDK-8* \
           /c/Program\ Files/Zulu/zulu-8* \
           /c/Program\ Files/Java/jdk1.8* \
           /c/Program\ Files/Java/jdk-8*; do
    [ -d "$d" ] || continue
    export JDK_18="${JDK_18:-$d}"; break
  done
  for d in /c/Program\ Files/Eclipse\ Adoptium/jdk-21* \
           /c/Program\ Files/Eclipse\ Adoptium/jdk-17* \
           /c/Program\ Files/Microsoft/jdk-21* \
           /c/Program\ Files/Microsoft/jdk-17* \
           /c/Program\ Files/BellSoft/LibericaJDK-21* \
           /c/Program\ Files/Zulu/zulu-21*; do
    [ -d "$d" ] || continue
    export JAVA_HOME="${JAVA_HOME_21:-$d}"; break
  done
  shopt -u nullglob
  [ -n "${JAVA_HOME_21:-}" ] && export JAVA_HOME="$JAVA_HOME_21"
fi

[ -n "${JAVA_HOME:-}" ] && export PATH="$JAVA_HOME/bin:$PATH"

echo "java -version: $(java -version 2>&1 | head -1 || echo missing)"

# --- Maven settings + Gradle wrapper (LAN) ---
if [ -n "$PROXY_URL" ]; then
  mkdir -p "$MAVEN_USER_HOME/.m2"
  KREPO="$MAVEN_USER_HOME/.m2/repository/org/jetbrains/kotlin"
  if [[ -d "$KREPO" ]]; then
    find "$KREPO" \( -name '*.lastUpdated' -o -name '_remote.repositories' \) -delete 2>/dev/null || true
  fi
  BUILD_REPO_ABS="$(cd "$KOTLIN_ROOT" && pwd -P)/build/repo"
  if [ "$RUNNER_OS" = "Windows" ]; then
    FILE_BUILD_REPO_URL="file:///$(cygpath -m "$BUILD_REPO_ABS")"
    MAVEN_LOCAL_REPO_FOR_XML="$(cygpath -m "$MAVEN_LOCAL_REPO")"
  else
    FILE_BUILD_REPO_URL="file://${BUILD_REPO_ABS}"
    MAVEN_LOCAL_REPO_FOR_XML="$MAVEN_LOCAL_REPO"
  fi
  LOCAL_BUILD_REPO_ID="kn-action-local-build-repo"
  LAN_RELEASES_ID="kn-action-lan-releases"
  cat >"$MAVEN_USER_HOME/.m2/settings.xml" <<EOF
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <localRepository>$MAVEN_LOCAL_REPO_FOR_XML</localRepository>
  <mirrors>
    <mirror>
      <id>maven-proxy</id>
      <mirrorOf>external:*</mirrorOf>
      <url>$PROXY_URL</url>
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
        <repository>
          <id>${LAN_RELEASES_ID}</id>
          <url>$PROXY_URL</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>${LOCAL_BUILD_REPO_ID}</id>
          <url>${FILE_BUILD_REPO_URL}</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </pluginRepository>
        <pluginRepository>
          <id>${LAN_RELEASES_ID}</id>
          <url>$PROXY_URL</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>
</settings>
EOF
  mkdir -p "$HOME/.m2"
  cp "$MAVEN_USER_HOME/.m2/settings.xml" "$HOME/.m2/settings.xml"
  export ORG_GRADLE_PROJECT_cacheRedirectorEnabled=false

  MP="$PROXY_URL"
  if [[ "$MP" == */releases ]]; then
    GRADLE_DIST_BASE="${MP%/releases}/distributions"
  else
    GRADLE_DIST_BASE="$DEFAULT_GRADLE_DISTRIBUTIONS_URL"
  fi
  bash "$CI_PROJECT_DIR/scripts/rewrite-gradle-wrapper-reposlite.sh" "$KOTLIN_ROOT" "$GRADLE_DIST_BASE"
fi

# --- Build (HOME aligned with Maven local repo, same as GHA) ---
export HOME="$MAVEN_USER_HOME"
export GRADLE_USER_HOME
export MAVEN_USER_HOME
export MAVEN_PROXY_URL="$PROXY_URL"
if [ -n "$PROXY_URL" ]; then
  export USE_CN_MIRROR="false"
else
  export USE_CN_MIRROR="${USE_CN_MIRROR:-true}"
fi
export KONAN_DATA_DIR
export MAVEN_OPTS="-Duser.home=${MAVEN_USER_HOME}"
export GRADLE_OPTS="-Dorg.gradle.internal.repository.max.tentatives=16 -Dorg.gradle.internal.repository.initial.backoff=5000 -Dorg.spdx.useJARLicenseInfoOnly=true"

if [ "$RUNNER_OS" = "macOS" ]; then
  export DEVELOPER_DIR="${XCODE_DEVELOPER_DIR:-/Applications/Xcode-26.2.app/Contents/Developer/}"
else
  export DEVELOPER_DIR="${DEVELOPER_DIR:-}"
fi

cd "$KOTLIN_ROOT"
# Workaround: build-ohos.sh's cleanDependencyCache sometimes fails on macOS
# when rm -rf hits a partially-locked gradle modules-2 directory.
sed -i.bak 's#rm -rf "\$gradleHome/caches/modules-2"#rm -rf "\$gradleHome/caches/modules-2" 2>/dev/null || true#' scripts/build-ohos.sh
bash scripts/build-ohos.sh
./gradlew --stop

# --- promote clean cache ---
if [ "$CLEAN_BUILD" = "true" ]; then
  if [ -d "$CLEAN_CACHE_ROOT" ]; then
    echo "Promoting clean build cache to $PERSISTED_CACHE_ROOT"
    rm -rf "$PERSISTED_CACHE_ROOT"
    mkdir -p "$PERSISTED_CACHE_ROOT"
    # shellcheck disable=SC2086
    mv "$CLEAN_CACHE_ROOT"/* "$PERSISTED_CACHE_ROOT/" 2>/dev/null || true
  fi
fi

# --- archive + upload ---
COMMIT_SHORT="${CI_COMMIT_SHA:0:7}"
if [ -z "${COMMIT_SHORT// }" ]; then
  COMMIT_SHORT="$(git -C "$CI_PROJECT_DIR" rev-parse --short=7 HEAD 2>/dev/null || echo local)"
fi
KOTLIN_SHA_SHORT="${KOTLIN_SHA:0:7}"
ARCHIVE_NAME="kotlin-${KOTLIN_SHA_SHORT}_act-${COMMIT_SHORT}_${RUNNER_OS}_${RUNNER_ARCH}.tar.gz"
OUT_PATH="$ARTIFACT_LOCAL_PATH/$ARCHIVE_NAME"
mkdir -p "$ARTIFACT_LOCAL_PATH"
tar -cf - -C "$KOTLIN_ROOT" build/repo | gzip -9 >"$OUT_PATH"

export INPUT_PATH="$OUT_PATH"
export INPUT_SERVER_URL="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
export INPUT_CACHE_DIR="$ARTIFACT_LOCAL_PATH"
KND="$(mktemp)"
export KNACTION_DOTENV_FILE="$KND"
# shellcheck source=/dev/null
source "$CI_PROJECT_DIR/.github/actions/upload-artifact-local/upload.sh"
rm -f "$KND"

echo "Kotlin build OK: $OUT_PATH"
