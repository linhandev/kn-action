#!/usr/bin/env bash
# GitLab CI port of .github/workflows/build-kotlin.yml (matrix: linux-x64, macos-arm64, macos-x64, windows-x64).
# Requires: GitCode SSH for kotlin clone; JDK 8 (JDK_18) and a modern JDK (JAVA_HOME) installed on the runner — no CI download/bootstrap.
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"

PLATFORM="${1:?usage: kotlin-build.sh linux-x64|macos-arm64|macos-x64|windows-x64}"

cd "$CI_PROJECT_DIR"

# shellcheck source=scripts/ci/artifact-server-latest.sh
source "$CI_PROJECT_DIR/scripts/ci/artifact-server-latest.sh"

case "$PLATFORM" in
  linux-x64) export RUNNER_OS=Linux; export RUNNER_ARCH=X64 ;;
  macos-arm64) export RUNNER_OS=macOS; export RUNNER_ARCH=ARM64 ;;
  macos-x64) export RUNNER_OS=macOS; export RUNNER_ARCH=X64 ;;
  windows-x64) export RUNNER_OS=Windows; export RUNNER_ARCH=X64 ;;
  *) echo "Unknown platform: $PLATFORM" >&2; exit 1 ;;
esac

# --- defaults (match build-kotlin.yml env) ---
export DEFAULT_KOTLIN_BRANCH="${DEFAULT_KOTLIN_BRANCH:-switch-llvm}"
export DEFAULT_CLEAN_BUILD="${DEFAULT_CLEAN_BUILD:-false}"
export DEFAULT_MAVEN_PROXY_URL="${DEFAULT_MAVEN_PROXY_URL:-http://192.168.3.5:8080/releases}"
export DEFAULT_GRADLE_DISTRIBUTIONS_URL="${DEFAULT_GRADLE_DISTRIBUTIONS_URL:-http://192.168.3.5:8080/distributions}"
export REPO_URL="${REPO_URL:-git@gitcode.com:linhandev/kotlin.git}"
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

# Volume-mounted checkouts may be owned by another uid (e.g. prior shell-executor jobs vs Docker root).
if command -v git >/dev/null 2>&1; then
  git config --global --add safe.directory '*' 2>/dev/null || git config --global --add safe.directory "$CI_PROJECT_DIR" 2>/dev/null || true
fi

# Job identity (shell executor: match keys to this HOME — Windows LocalSystem → .../systemprofile/.ssh).
echo "=== kotlin-build CI identity ===" >&2
echo "whoami=$(whoami 2>/dev/null || true) HOME=${HOME:-}" >&2
echo "GITCODE_SSH_PRIVATE_KEY=$([ -n "${GITCODE_SSH_PRIVATE_KEY:-}" ] && echo set || echo unset)" >&2
ls -la "${HOME}/.ssh" 2>/dev/null | head -12 >&2 || true
echo "=== end kotlin-build CI identity ===" >&2

# GitCode SSH: explicit GIT_SSH_COMMAND on Linux/macOS (no ssh-agent). Windows: block below.
# GitLab CI "File" variables expand to a path — copy the file; do not printf the path as key material.
kotlin_gitcode_materialize_key() {
  local dest="${1:?}"
  if [ -z "${GITCODE_SSH_PRIVATE_KEY:-}" ]; then
    return 1
  fi
  if [ -f "$GITCODE_SSH_PRIVATE_KEY" ] && [ -r "$GITCODE_SSH_PRIVATE_KEY" ]; then
    cp "$GITCODE_SSH_PRIVATE_KEY" "$dest"
    echo "kotlin_gitcode_ssh_env: using GITCODE_SSH_PRIVATE_KEY as file (GitLab File-type / path)" >&2
  else
    printf '%s\n' "$GITCODE_SSH_PRIVATE_KEY" >"$dest"
    echo "kotlin_gitcode_ssh_env: using GITCODE_SSH_PRIVATE_KEY as inline key material" >&2
  fi
  chmod 600 "$dest"
}

kotlin_gitcode_ssh_env() {
  : "${RUNNER_TEMP:?RUNNER_TEMP must be set}"
  mkdir -p "$RUNNER_TEMP"
  local _gk="${RUNNER_TEMP}/gitcode_known_hosts"
  ssh-keyscan -t ed25519,ecdsa,rsa gitcode.com >>"$_gk" 2>/dev/null || true

  if [ -n "${GITCODE_SSH_PRIVATE_KEY:-}" ]; then
    local _wk="${RUNNER_TEMP}/gitcode_id_ed25519"
    kotlin_gitcode_materialize_key "$_wk"
    if [ "${RUNNER_OS:-}" = "Windows" ]; then
      local idf gkf
      idf="$(cygpath -m "$_wk" 2>/dev/null || echo "$_wk")"
      gkf="$(cygpath -m "$_gk" 2>/dev/null || echo "$_gk")"
      export GIT_SSH_COMMAND="ssh -i ${idf} -o IdentitiesOnly=yes -o UserKnownHostsFile=${gkf} -o StrictHostKeyChecking=yes"
    else
      export GIT_SSH_COMMAND="ssh -i ${_wk} -o IdentitiesOnly=yes -o UserKnownHostsFile=${_gk} -o StrictHostKeyChecking=yes"
    fi
    echo "kotlin_gitcode_ssh_env: GITCODE_SSH_PRIVATE_KEY (CI variable)" >&2
    return 0
  fi

  local _key=""
  if [ -f "${HOME}/.ssh/id_ed25519" ]; then
    _key="${HOME}/.ssh/id_ed25519"
  elif [ -f "${HOME}/.ssh/id_rsa" ]; then
    _key="${HOME}/.ssh/id_rsa"
  fi
  if [ -z "$_key" ]; then
    echo "kotlin_gitcode_ssh_env: warning: no GITCODE_SSH_PRIVATE_KEY and no ~/.ssh/id_ed25519 or id_rsa (HOME=${HOME:-})" >&2
    return 0
  fi

  if [ "${RUNNER_OS:-}" = "Windows" ]; then
    local idf gkf
    idf="$(cygpath -m "$_key" 2>/dev/null || echo "$_key")"
    if [ -f "${HOME}/.ssh/known_hosts" ]; then
      gkf="$(cygpath -m "${HOME}/.ssh/known_hosts" 2>/dev/null || echo "${HOME}/.ssh/known_hosts")"
    else
      gkf="$(cygpath -m "$_gk" 2>/dev/null || echo "$_gk")"
    fi
    export GIT_SSH_COMMAND="ssh -i ${idf} -o IdentitiesOnly=yes -o UserKnownHostsFile=${gkf} -o StrictHostKeyChecking=yes"
  elif [ -f "${HOME}/.ssh/known_hosts" ]; then
    export GIT_SSH_COMMAND="ssh -i ${_key} -o IdentitiesOnly=yes -o UserKnownHostsFile=${HOME}/.ssh/known_hosts -o StrictHostKeyChecking=yes"
  else
    export GIT_SSH_COMMAND="ssh -i ${_key} -o IdentitiesOnly=yes -o UserKnownHostsFile=${_gk} -o StrictHostKeyChecking=yes"
  fi
  echo "kotlin_gitcode_ssh_env: ${_key}" >&2
  return 0
}
kotlin_gitcode_ssh_env

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

# --- macOS: Xcode tool presence ---
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

# prepare-repo runs Gradle --stop on reused Windows workspaces; must match this job's GRADLE_USER_HOME / opts.
export GRADLE_USER_HOME
# GitLab pre_get_sources_script may set GRADLE_OPTS; keep same defaults for local/GHA runs.
export GRADLE_OPTS="${GRADLE_OPTS:--Dorg.gradle.daemon=false -Dorg.gradle.internal.repository.max.tentatives=16 -Dorg.gradle.internal.repository.initial.backoff=5000 -Dorg.spdx.useJARLicenseInfoOnly=true}"

if [ "$CLEAN_BUILD" = "true" ]; then
  echo "Clean build: wiping Konan and Maven user home under cache root"
  rm -rf "$KONAN_DATA_DIR"
  mkdir -p "$KONAN_DATA_DIR"
  rm -rf "$MAVEN_USER_HOME"
  mkdir -p "$MAVEN_USER_HOME/.m2"
fi

# Fail fast when using git@ (GitCode SSH) but no key was configured (see "kotlin-build CI identity" above).
case "${REPO_URL:-}" in
  git@*)
    if [ -z "${GIT_SSH_COMMAND:-}" ]; then
      cat >&2 <<'EOF'
kotlin-build: cannot clone Kotlin over SSH — no private key.

Set CI/CD variable GITCODE_SSH_PRIVATE_KEY (File or multiline), or install id_ed25519 (or id_rsa) under the job user's HOME/.ssh.

Windows (runner as LocalSystem): HOME is %SystemRoot%\System32\config\systemprofile — copy the same key there or run scripts/ci/windows-runner-systemprofile-gitcode-ssh.ps1 once as Administrator.
EOF
      exit 2
    fi
    ;;
esac

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
echo "=== Kotlin sync completed ==="
echo "Repository: $REPO_URL"
echo "Branch: ${BRANCH:-<detached/commit>}"
echo "HEAD: $KOTLIN_SHA"
echo "Last 5 commits after Kotlin sync:"
GIT_PAGER=cat git -C "$KOTLIN_ROOT" log -n 5 --date=iso --pretty=format:'%h %ad %an %s' || true
echo "=== End Kotlin sync summary ==="

# --- patch ---
PATCH="$CI_PROJECT_DIR/patches/kotlin-js-tests-npmSetRegistry.patch"
cd "$KOTLIN_ROOT"
if command -v patch >/dev/null 2>&1 && patch -p1 <"$PATCH"; then
  echo "Applied kotlin-js-tests-npmSetRegistry patch"
elif grep -q 'if (cacheRedirectorEnabled)' js/js.tests/build.gradle.kts 2>/dev/null; then
  echo "kotlin-js-tests guard already present; skipping patch"
else
  echo "ERROR: patch unavailable or failed and js/js.tests/build.gradle.kts lacks expected guard" >&2
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
  # Prefer well-known paths, then any /usr/lib/jvm/* whose java reports 8 / 1.8 (Temurin, Corretto, etc.).
  for d in /usr/lib/jvm/java-8-openjdk-amd64 /usr/lib/jvm/java-1.8.0-openjdk-amd64 \
           /usr/lib/jvm/java-8-openjdk /usr/lib/jvm/zulu-8 \
           /usr/lib/jvm/temurin-8-jdk-amd64 /usr/lib/jvm/temurin-8-jdk-x64 \
           /usr/lib/jvm/java-1.8.0-amazon-corretto /usr/lib/jvm/amazon-corretto-8 \
           /usr/lib/jvm/liberica-jdk-8 /usr/lib/jvm/java-8-oracle; do
    [ -d "$d" ] && [ -x "$d/bin/java" ] && export JDK_18="${JDK_18:-$d}" && break
  done
  if [ -z "${JDK_18:-}" ] && [ -d /usr/lib/jvm ]; then
    shopt -s nullglob
    for d in /usr/lib/jvm/*; do
      [ -d "$d" ] || continue
      [ -x "$d/bin/java" ] || continue
      _jv="$("$d/bin/java" -version 2>&1 | head -1 || true)"
      if echo "$_jv" | grep -qE 'version "(1\.8|8\.)'; then
        export JDK_18="$d"
        echo "kotlin-build: resolved JDK_18 on Linux via scan: $d ($_jv)" >&2
        break
      fi
    done
    shopt -u nullglob
  fi
  for d in /usr/lib/jvm/java-21-openjdk-amd64 /usr/lib/jvm/java-21-openjdk \
           /usr/lib/jvm/temurin-21-amd64 /usr/lib/jvm/temurin-21-jdk-amd64 /usr/lib/jvm/temurin-21-jdk-x64 \
           /usr/lib/jvm/java-11-openjdk; do
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

# Linux/Windows shell CI: require preinstalled JDKs (no download in this script).
_kotlin_java_bin_ok() {
  local home="${1:?}"
  [ -x "${home}/bin/java" ] || [ -x "${home}/bin/java.exe" ] || [ -f "${home}/bin/java.exe" ]
}

if [ -n "${CI:-}" ] && { [ "$RUNNER_OS" = "Linux" ] || [ "$RUNNER_OS" = "Windows" ]; }; then
  if [ -z "${JAVA_HOME:-}" ] || ! _kotlin_java_bin_ok "$JAVA_HOME"; then
    cat >&2 <<'EOF'
kotlin-build: JAVA_HOME is unset or has no bin/java. Install a modern JDK (e.g. 17 or 21) on the runner, or set JAVA_HOME / JAVA_HOME_21.
EOF
    exit 2
  fi
  if [ -z "${JDK_18:-}" ] || ! _kotlin_java_bin_ok "$JDK_18"; then
    cat >&2 <<'EOF'
kotlin-build: JDK_18 is unset or has no bin/java. Install JDK 8 on the runner, or set JDK_18 / JAVA_HOME_8.
EOF
    exit 2
  fi
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
# GRADLE_OPTS / GRADLE_USER_HOME already set before prepare-repo (clone step).

if [ "$RUNNER_OS" = "macOS" ]; then
  export DEVELOPER_DIR="${XCODE_DEVELOPER_DIR:-/Applications/Xcode-26.2.app/Contents/Developer/}"
else
  export DEVELOPER_DIR="${DEVELOPER_DIR:-}"
fi

# Maps kotlin-build.sh platform to kotlin.native.llvm.default.* property suffix in kotlin-native/gradle.properties
gradle_llvm_default_suffix_for_platform() {
  case "${1:?}" in
    linux-x64) echo linux_x64 ;;
    macos-arm64) echo macos_arm64 ;;
    macos-x64) echo macos_x64 ;;
    windows-x64) echo mingw_x64 ;;
    *) echo "" ;;
  esac
}

# Regex for merged OH LLVM final archives on the LAN server (see platform_package.sh / llvm-provide-artifacts).
# artifact-server /artifacts/latest picks newest mtime match (infra/artifact-server/main.py).
_kotlin_llvm_latest_regex_for_platform() {
  case "${1:?}" in
    linux-x64) echo '^llvm-[0-9]+-x86_64-linux-dev-oh-[0-9]+_.*\.tar\.gz$' ;;
    macos-arm64) echo '^llvm-[0-9]+-aarch64-macos-dev-oh-[0-9]+_.*\.tar\.gz$' ;;
    macos-x64) echo '^llvm-[0-9]+-x86_64-macos-dev-oh-[0-9]+_.*\.tar\.gz$' ;;
    windows-x64) echo '^llvm-[0-9]+-x86_64-windows-dev-oh-[0-9]+_.*\.zip$' ;;
    *) echo "" ;;
  esac
}

# Resolve final host LLVM archive: KOTLIN_FRESH_LLVM_ARCHIVE, else llvm-artifacts.env from llvm:provide-artifacts, else latest on ARTIFACT_SERVER_URL by regex.
resolve_fresh_llvm_archive_filename() {
  local platform="${1:?}"
  if [ -n "${KOTLIN_FRESH_LLVM_ARCHIVE:-}" ]; then
    echo "$KOTLIN_FRESH_LLVM_ARCHIVE"
    return 0
  fi
  local envfile="${CI_PROJECT_DIR:-}/llvm-artifacts.env"
  if [ -f "$envfile" ]; then
    # shellcheck disable=SC1090
    set -a && source "$envfile" && set +a
    case "$platform" in
      linux-x64)
        [ -n "${archive_linux:-}" ] && {
          echo "${archive_linux}"
          return 0
        }
        ;;
      macos-arm64)
        [ -n "${archive_mac_arm64:-}" ] && {
          echo "${archive_mac_arm64}"
          return 0
        }
        ;;
      macos-x64)
        [ -n "${archive_mac_x64:-}" ] && {
          echo "${archive_mac_x64}"
          return 0
        }
        ;;
      windows-x64)
        [ -n "${archive_windows:-}" ] && {
          echo "${archive_windows}"
          return 0
        }
        ;;
    esac
  fi
  local server pattern name
  server="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
  pattern="$(_kotlin_llvm_latest_regex_for_platform "$platform")"
  [ -n "$pattern" ] || {
    echo ""
    return 0
  }
  if name="$(artifact_server_latest_basename "$server" "$pattern")"; then
    echo "$name"
    return 0
  fi
  echo ""
  return 0
}

# Download OH merged LLVM, install under $KONAN_DATA_DIR/dependencies/<stem>, update .extracted,
# and point kotlin.native.llvm.default.<host>.{dev,essentials} at remote:public/<stem> for this runner only.
install_fresh_llvm_for_konan() {
  local platform="${1:?}"
  if [ "${KOTLIN_USE_FRESH_LLVM:-true}" = "false" ]; then
    echo "Fresh LLVM for Konan disabled (KOTLIN_USE_FRESH_LLVM=false)"
    return 0
  fi

  local archive_name
  archive_name="$(resolve_fresh_llvm_archive_filename "$platform")"
  if [ -z "$archive_name" ]; then
    echo "No fresh LLVM archive name (set KOTLIN_FRESH_LLVM_ARCHIVE, or llvm-artifacts.env from llvm:provide-artifacts, or ensure ARTIFACT_SERVER_URL has a latest merged OH LLVM match); using kotlin-native/gradle.properties defaults"
    return 0
  fi

  local gradle_sfx
  gradle_sfx="$(gradle_llvm_default_suffix_for_platform "$platform")"
  if [ -z "$gradle_sfx" ]; then
    echo "Unknown platform for LLVM gradle mapping: $platform" >&2
    return 1
  fi

  local server="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
  local dl="$RUNNER_TEMP/fresh-llvm/$archive_name"
  mkdir -p "$(dirname "$dl")"
  echo "Downloading fresh LLVM for Konan: $server/artifacts/$archive_name"
  if ! curl -fsSL -o "$dl" "$server/artifacts/$archive_name"; then
    echo "Failed to download $archive_name; check artifact server or set KOTLIN_USE_FRESH_LLVM=false to skip" >&2
    return 1
  fi

  local work="$RUNNER_TEMP/fresh-llvm/extract"
  rm -rf "$work"
  mkdir -p "$work"
  if [[ "$dl" == *.zip ]]; then
    unzip -q "$dl" -d "$work"
  else
    if command -v pigz >/dev/null 2>&1; then
      pigz -dc "$dl" | tar -xf - -C "$work"
    else
      tar -xzf "$dl" -C "$work"
    fi
  fi

  local stem
  stem="$(find "$work" -maxdepth 1 -type d -name 'llvm-*-dev-*' -print 2>/dev/null | head -1)"
  stem="${stem##*/}"
  if [ -z "$stem" ] || [ ! -d "$work/$stem" ]; then
    echo "Expected top-level llvm-*-dev-* directory after extract" >&2
    ls -la "$work" >&2 || true
    return 1
  fi

  mkdir -p "$KONAN_DATA_DIR/dependencies"
  rm -rf "${KONAN_DATA_DIR:?}/dependencies/${stem}"
  mv "$work/$stem" "$KONAN_DATA_DIR/dependencies/"
  touch "$KONAN_DATA_DIR/dependencies/.extracted"
  if ! grep -qxF "$stem" "$KONAN_DATA_DIR/dependencies/.extracted" 2>/dev/null; then
    echo "$stem" >>"$KONAN_DATA_DIR/dependencies/.extracted"
  fi
  echo "Installed LLVM dependency at $KONAN_DATA_DIR/dependencies/$stem (recorded in .extracted)"

  local gf="$KOTLIN_ROOT/kotlin-native/gradle.properties"
  if [ ! -f "$gf" ]; then
    echo "kotlin-native/gradle.properties not found at $gf; skipping LLVM default rewrite" >&2
    return 0
  fi
  cp "$gf" "${gf}.pre-fresh-llvm.bak"
  sed -i.bak \
    -e "s|^kotlin\\.native\\.llvm\\.default\\.${gradle_sfx}\\.dev=.*|kotlin.native.llvm.default.${gradle_sfx}.dev=remote:public/${stem}|" \
    -e "s|^kotlin\\.native\\.llvm\\.default\\.${gradle_sfx}\\.essentials=.*|kotlin.native.llvm.default.${gradle_sfx}.essentials=remote:public/${stem}|" \
    "$gf"
  echo "Pointed kotlin.native.llvm.default.${gradle_sfx}.{dev,essentials} at remote:public/${stem} ($gf)"
}

cd "$KOTLIN_ROOT"

KONAN_PROXY_BASE="http://192.168.3.5:8080/file-storage"

rewrite_konan_properties() {
  local props_file="$1"
  if [ -f "$props_file" ]; then
    sed -i.bak \
      -e "s|dependenciesUrl = https://maven\.eazytec-cloud\.com/nexus/repository/file-storage|dependenciesUrl = ${KONAN_PROXY_BASE}|g" \
      -e "s|dependenciesUrl = https://download\.jetbrains\.com/kotlin/native|dependenciesUrl = ${KONAN_PROXY_BASE}|g" \
      "$props_file"
    echo "Rewrote konan.properties ($props_file)"
  fi
}

for cand in \
  "$CI_PROJECT_DIR/ci-workspace/kotlin-native/konan/konan.properties" \
  "$KOTLIN_ROOT/native/konan.properties" \
  "$KOTLIN_ROOT/konan/konan.properties" \
  "$KOTLIN_ROOT/kotlin-native/konan/konan.properties"; do
  [ -f "$cand" ] && rewrite_konan_properties "$cand"
done

# kotlin-native/dependencies/build.gradle.kts — e.g. repositoryURL.set("https://maven.eazytec-cloud.com/nexus/repository/file-storage") → LAN raw mirror.
DEPS_GRADLE_KTS="$KOTLIN_ROOT/kotlin-native/dependencies/build.gradle.kts"
if [ -f "$DEPS_GRADLE_KTS" ]; then
  cp "$DEPS_GRADLE_KTS" "${DEPS_GRADLE_KTS}.pre-mirror.bak"
  sed -i.bak \
    -e "s|https://maven\\.eazytec-cloud\\.com/nexus/repository/file-storage|${KONAN_PROXY_BASE}|g" \
    "$DEPS_GRADLE_KTS"
  echo "Rewrote file-storage URL in kotlin-native/dependencies/build.gradle.kts -> ${KONAN_PROXY_BASE}"
fi

install_fresh_llvm_for_konan "$PLATFORM"

echo "=== kotlin.native.llvm.default.* (kotlin-native/gradle.properties) — LLVM version switch uses sed here, not patches/ ==="
if [ -f "$KOTLIN_ROOT/kotlin-native/gradle.properties" ]; then
  grep '^kotlin\.native\.llvm\.default\.' "$KOTLIN_ROOT/kotlin-native/gradle.properties" 2>/dev/null | head -40 || echo "(no kotlin.native.llvm.default.* lines)"
else
  echo "(kotlin-native/gradle.properties missing)"
fi
if [ "${KOTLIN_USE_FRESH_LLVM:-true}" = "false" ]; then
  echo "KOTLIN_USE_FRESH_LLVM=false (pipeline input kotlin_use_fresh_llvm): kotlin-native/gradle.properties was not rewritten to remote:public/<stem>." >&2
elif [ -f "$KOTLIN_ROOT/kotlin-native/gradle.properties" ] && git -C "$KOTLIN_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  && ! git -C "$KOTLIN_ROOT" diff --no-ext-diff --quiet -- kotlin-native/gradle.properties 2>/dev/null; then
  echo "Fresh LLVM rewrote kotlin-native/gradle.properties." >&2
elif [ "${KOTLIN_USE_FRESH_LLVM:-true}" != "false" ]; then
  echo "No change to kotlin-native/gradle.properties from fresh-LLVM defaults (or archive missing / download failed)." >&2
fi

BUILD_OHOS="$KOTLIN_ROOT/scripts/build-ohos.sh"
if [ -f "$BUILD_OHOS" ]; then
  awk '/^run_gradle --stop$/ { print; print "for f in ./kotlin-native/konan/konan.properties ./kotlin-native/dist/konan/konan.properties; do [ -f \"$f\" ] && sed -i.bak -e \"s|dependenciesUrl = https://maven.eazytec-cloud.com/nexus/repository/file-storage|dependenciesUrl = http://192.168.3.5:8080/file-storage|g\" -e \"s|dependenciesUrl = https://download.jetbrains.com/kotlin/native|dependenciesUrl = http://192.168.3.5:8080/file-storage|g\" \"$f\"; done"; next } { print }' "$BUILD_OHOS" > "$BUILD_OHOS.bak2" && mv "$BUILD_OHOS.bak2" "$BUILD_OHOS"
fi

rm -rf "$KOTLIN_ROOT/.gradle/configuration-cache" "$KOTLIN_ROOT/kotlin-native/.gradle/configuration-cache" 2>/dev/null || true

sed -i.bak 's#rm -rf "\$gradleHome/caches/modules-2"#rm -rf "\$gradleHome/caches/modules-2" 2>/dev/null || true#' scripts/build-ohos.sh
bash scripts/build-ohos.sh

./gradlew --stop

# Kotlin compiler version for downstream (HAP job passes -PkotlinVersion=…)
KVER=""
if [[ -f "$KOTLIN_ROOT/gradle.properties" ]]; then
  KVER=$(grep -E '^version=' "$KOTLIN_ROOT/gradle.properties" | head -1 | cut -d= -f2- | tr -d ' \r' || true)
fi
if [[ -z "$KVER" ]]; then
  KVER=$(grep -E '^build_version=' "$KOTLIN_ROOT/gradle.properties" | head -1 | cut -d= -f2- | tr -d ' \r' || true)
fi

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

ARTIFACT_SERVER_URL_EFFECTIVE="${ARTIFACT_SERVER_URL:-http://192.168.3.5:8765}"
{
  echo "KOTLIN_VERSION=${KVER:-}"
  echo "KOTLIN_SHA=${KOTLIN_SHA}"
  echo "ARTIFACT_SERVER_URL=${ARTIFACT_SERVER_URL_EFFECTIVE}"
  echo "KOTLIN_ARTIFACT_BASENAME=${ARCHIVE_NAME}"
} >"$KOTLIN_ROOT/kotlin-version.env"

echo "Kotlin build OK: $OUT_PATH"
