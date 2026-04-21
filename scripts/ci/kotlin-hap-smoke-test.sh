#!/usr/bin/env bash
# Smoke-test: download build/repo from LAN artifact server, find Kotlin/Native prebuilt inside that Maven tree,
# clone kn_samples bare, align kotlinVersion with the compiler build, run HAP on device.
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/logging.sh"

# Injected by GitLab dotenv from build:kotlin:macos:arm64 (kotlin-version.env)
: "${KOTLIN_VERSION:?KOTLIN_VERSION missing (dotenv from kotlin build)}"
: "${ARTIFACT_SERVER_URL:?ARTIFACT_SERVER_URL missing}"
: "${KOTLIN_ARTIFACT_BASENAME:?KOTLIN_ARTIFACT_BASENAME missing}"

SERVER="${ARTIFACT_SERVER_URL%/}"

WORK_DIR="$CI_PROJECT_DIR/kn-samples-work"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

DL="$WORK_DIR/dl"
mkdir -p "$DL"

log_info "Downloading build/repo archive: $SERVER/artifacts/$KOTLIN_ARTIFACT_BASENAME"
curl -fsSL -o "$DL/build-repo.tgz" "$SERVER/artifacts/$KOTLIN_ARTIFACT_BASENAME"

mkdir -p "$DL/extract-repo"
tar -xzf "$DL/build-repo.tgz" -C "$DL/extract-repo"
export KN_ACTION_BUILD_REPO_ABS
KN_ACTION_BUILD_REPO_ABS="$(cd "$DL/extract-repo/build/repo" && pwd -P)"
log_info "KN_ACTION_BUILD_REPO_ABS=$KN_ACTION_BUILD_REPO_ABS"

# kotlin.native.home: use prebuilt K/N tarball published under build/repo (Maven layout), not a separate host upload.
KN_TARBALL_IN_REPO="$(find "$KN_ACTION_BUILD_REPO_ABS" -type f -name 'kotlin-native-macos-aarch64-*.tar.gz' 2>/dev/null | head -1 || true)"
if [[ -z "$KN_TARBALL_IN_REPO" || ! -f "$KN_TARBALL_IN_REPO" ]]; then
  log_error "No kotlin-native-macos-aarch64 *.tar.gz under build/repo (expected kotlin-native-prebuilt in Maven repo)"
  find "$KN_ACTION_BUILD_REPO_ABS" -maxdepth 5 -type f -name '*.tar.gz' 2>/dev/null | head -20 || true
  exit 1
fi
log_info "Using Kotlin/Native prebuilt from build/repo: $KN_TARBALL_IN_REPO"

mkdir -p kn-dist
tar -xzf "$KN_TARBALL_IN_REPO" -C kn-dist
KN_DIST_ROOT="$(find "$WORK_DIR/kn-dist" -maxdepth 1 -type d | head -2 | tail -1 || true)"
if [[ -z "$KN_DIST_ROOT" || ! -d "$KN_DIST_ROOT/bin" ]]; then
  log_error "Expected Kotlin/Native dist directory after extract"
  ls -la "$WORK_DIR/kn-dist" || true
  exit 1
fi
log_info "Kotlin/Native home: $KN_DIST_ROOT"

SAMPLES_REPO="${KN_SAMPLES_REPO:-ssh://git@192.168.3.6:2222/linhandev/kn_samples.git}"
SAMPLES_BRANCH="${KN_SAMPLES_BRANCH:-bare}"
git clone --depth 1 --branch "$SAMPLES_BRANCH" "$SAMPLES_REPO" kn_samples
cd kn_samples

# bare branch reads kotlinVersion from gradle.properties; CI passes -P to match the built compiler.
if grep -q '^kotlin.native.home=' gradle.properties 2>/dev/null; then
  sed -i.bak "s|^kotlin.native.home=.*|kotlin.native.home=$KN_DIST_ROOT|" gradle.properties
else
  echo "kotlin.native.home=$KN_DIST_ROOT" >> gradle.properties
fi
log_info "Set kotlin.native.home=$KN_DIST_ROOT in gradle.properties"

HDC_BIN="$(command -v hdc || true)"
if [[ -z "$HDC_BIN" || ! -x "$HDC_BIN" ]]; then
  log_error "hdc not found on PATH"
  exit 1
fi
log_info "hdc: $HDC_BIN"

if ! "$HDC_BIN" list targets 2>/dev/null | grep -q .; then
  log_error "No hdc targets connected"
  "$HDC_BIN" list targets || true
  exit 1
fi
HDC_TARGET="$("$HDC_BIN" list targets 2>/dev/null | head -1 | tr -d '\r' | awk '{print $1}')"
log_info "hdc target: $HDC_TARGET"

BUNDLE_NAME="$(grep '"bundleName"' harmonyApp/AppScope/app.json5 | sed -n 's/.*"bundleName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr -d '\r')"
[[ -n "$BUNDLE_NAME" ]] || { log_error "bundleName not found in harmonyApp/AppScope/app.json5"; exit 1; }
log_info "Bundle name: $BUNDLE_NAME"

log_info "Uninstalling previous app..."
"$HDC_BIN" -t "$HDC_TARGET" uninstall "$BUNDLE_NAME" 2>/dev/null || true

BEFORE=""
BEFORE="$("$HDC_BIN" -t "$HDC_TARGET" shell "ls -t /data/log/faultlog/faultlogger/" 2>/dev/null | tr -d '\r' | grep -F "$BUNDLE_NAME" | head -1 || true)"
[[ -n "$BEFORE" ]] && log_info "Pre-run faultlog: $BEFORE"

DEVECO_STUDIO_DIR="${DEVECO_STUDIO_DIR:-/Applications/DevEco-Studio.app}"
DEVECO_SDK_HOME="$DEVECO_STUDIO_DIR/Contents/sdk"
NODE_HOME="$DEVECO_STUDIO_DIR/Contents/tools/node"
export DEVECO_SDK_HOME NODE_HOME
log_info "DevEco SDK: $DEVECO_SDK_HOME"

pkill -f 'hvigor' 2>/dev/null || true
rm -rf ~/.hvigor/daemon/cache/*.json ~/.hvigor/project_caches/* 2>/dev/null || true
log_info "Cleaned hvigor daemon cache"

log_info "Building and launching HAP (kotlinVersion=$KOTLIN_VERSION)..."
if ! ./gradlew :kotlinApp:startHarmonyAppDebug \
  -PkotlinVersion="$KOTLIN_VERSION" \
  --rerun-tasks \
  --no-daemon \
  --refresh-dependencies; then
  log_error "Gradle build/start failed"
  exit 1
fi

log_info "Verifying app installation..."
if ! "$HDC_BIN" -t "$HDC_TARGET" shell "bm dump -n $BUNDLE_NAME" >/dev/null 2>&1; then
  log_error "App was not installed on the device (bm dump failed for $BUNDLE_NAME)"
  exit 1
fi

sleep 3

APP_PID="$("$HDC_BIN" -t "$HDC_TARGET" shell "ps -ef | grep $BUNDLE_NAME | grep -v grep" 2>/dev/null | awk '{print $2}' | head -1 || true)"
if [[ -z "$APP_PID" ]]; then
  log_error "App process not found after launch"
  exit 1
fi
log_info "App running with PID: $APP_PID"

LOGCAT_FILE="$WORK_DIR/logcat-after-launch.txt"
timeout 10 "$HDC_BIN" -t "$HDC_TARGET" shell "logcat -d" > "$LOGCAT_FILE" 2>/dev/null || true
if grep -qE "FATAL|crash|signal 11|SIGSEGV|Abort message" "$LOGCAT_FILE"; then
  log_error "Crash patterns found in logcat"
  grep -E "FATAL|crash|signal|Abort" "$LOGCAT_FILE" | head -20 >&2
  exit 1
fi

sleep 5
APP_PID_AFTER="$("$HDC_BIN" -t "$HDC_TARGET" shell "ps -ef | grep $BUNDLE_NAME | grep -v grep" 2>/dev/null | awk '{print $2}' | head -1 || true)"
if [[ -z "$APP_PID_AFTER" ]]; then
  log_error "App process died after 8 seconds (late crash)"
  exit 1
fi
log_info "App stable for 8+ seconds"

AFTER="$("$HDC_BIN" -t "$HDC_TARGET" shell "ls -t /data/log/faultlog/faultlogger/" 2>/dev/null | tr -d '\r' | grep -F "$BUNDLE_NAME" | head -1 || true)"

if [[ -n "$AFTER" && "$BEFORE" != "$AFTER" ]]; then
  mkdir -p "$WORK_DIR/crash-check"
  "$HDC_BIN" -t "$HDC_TARGET" file recv "/data/log/faultlog/faultlogger/$AFTER" "$WORK_DIR/crash-check/"
  CRASH_FILE="$WORK_DIR/crash-check/$AFTER"
  if grep -qE '^Reason:Signal:|^Reason:.*[Aa]bort' "$CRASH_FILE"; then
    log_error "Crash detected in faultlog: $AFTER"
    tail -n +19 "$CRASH_FILE" | head -n 50 >&2
    exit 1
  else
    log_info "New faultlog found but not a Signal/Abort crash: $AFTER"
  fi
fi

log_info "HAP smoke test passed: app installed and no crash detected."
