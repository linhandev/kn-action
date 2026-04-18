#!/usr/bin/env bash
# Smoke-test a freshly-built Kotlin/Native compiler by building the kn_samples bare branch
# into a HarmonyOS HAP, installing it, and asserting it does not crash on a connected device.
set -euo pipefail

: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/logging.sh"

# --- locate Kotlin/Native distribution tarball produced by the build job ---
KN_TARBALL="$(ls -1 "$CI_PROJECT_DIR/ci-workspace/kotlin-native"/kotlin-native-macos-aarch64-*.tar.gz 2>/dev/null | head -1 || true)"
if [[ -z "$KN_TARBALL" || ! -f "$KN_TARBALL" ]]; then
  log_error "Kotlin/Native tarball not found in ci-workspace/kotlin-native/"
  ls -la "$CI_PROJECT_DIR/ci-workspace/kotlin-native/" 2>/dev/null || true
  exit 1
fi
log_info "Using Kotlin/Native tarball: $KN_TARBALL"

# --- prepare workspace ---
WORK_DIR="$CI_PROJECT_DIR/kn-samples-work"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# --- extract Kotlin/Native distribution ---
mkdir -p kn-dist
tar -xzf "$KN_TARBALL" -C kn-dist
KN_DIST_ROOT="$(find "$WORK_DIR/kn-dist" -maxdepth 1 -type d | head -2 | tail -1 || true)"
if [[ -z "$KN_DIST_ROOT" || ! -d "$KN_DIST_ROOT/bin" ]]; then
  log_error "Expected Kotlin/Native dist directory after extract"
  ls -la "$WORK_DIR/kn-dist" || true
  exit 1
fi
log_info "Kotlin/Native home: $KN_DIST_ROOT"

# --- clone kn_samples bare branch ---
SAMPLES_REPO="${KN_SAMPLES_REPO:-https://github.com/linhandev/kn_samples.git}"
SAMPLES_BRANCH="${KN_SAMPLES_BRANCH:-bare}"
git clone --depth 1 --branch "$SAMPLES_BRANCH" "$SAMPLES_REPO" kn_samples
cd kn_samples

# --- point gradle at the freshly-built Kotlin/Native compiler ---
# Append to gradle.properties so it overrides any existing kotlin.native.home
if grep -q '^kotlin.native.home=' gradle.properties 2>/dev/null; then
  sed -i.bak "s|^kotlin.native.home=.*|kotlin.native.home=$KN_DIST_ROOT|" gradle.properties
else
  echo "kotlin.native.home=$KN_DIST_ROOT" >> gradle.properties
fi
log_info "Set kotlin.native.home=$KN_DIST_ROOT in gradle.properties"

# --- verify hdc is available ---
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

# --- resolve bundle name ---
BUNDLE_NAME="$(grep '"bundleName"' harmonyApp/AppScope/app.json5 | sed -n 's/.*"bundleName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr -d '\r')"
[[ -n "$BUNDLE_NAME" ]] || { log_error "bundleName not found in harmonyApp/AppScope/app.json5"; exit 1; }
log_info "Bundle name: $BUNDLE_NAME"

# --- uninstall previous app ---
log_info "Uninstalling previous app..."
"$HDC_BIN" -t "$HDC_TARGET" uninstall "$BUNDLE_NAME" 2>/dev/null || true

# --- record pre-run crash log (newest matching file) ---
BEFORE=""
BEFORE="$("$HDC_BIN" -t "$HDC_TARGET" shell "ls -t /data/log/faultlog/faultlogger/" 2>/dev/null | tr -d '\r' | grep -F "$BUNDLE_NAME" | head -1 || true)"
[[ -n "$BEFORE" ]] && log_info "Pre-run faultlog: $BEFORE"

# --- build and run HAP ---
log_info "Building and launching HAP..."
if ! ./gradlew :kotlinApp:startHarmonyAppDebug --rerun-tasks --no-daemon; then
  log_error "Gradle build/start failed"
  exit 1
fi

# --- verify the app was actually installed ---
log_info "Verifying app installation..."
if ! "$HDC_BIN" -t "$HDC_TARGET" shell "bm dump -n $BUNDLE_NAME" >/dev/null 2>&1; then
  log_error "App was not installed on the device (bm dump failed for $BUNDLE_NAME)"
  exit 1
fi

# --- wait a moment for app to settle ---
sleep 3

# --- check for new crash log ---
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
