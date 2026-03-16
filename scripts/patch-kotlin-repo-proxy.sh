#!/usr/bin/env bash
# Patch Kotlin repo Gradle files to use local Maven proxy instead of
# cache-redirector.jetbrains.com and redirector.kotlinlang.org.
# Usage: WORKSPACE_DIR=<path> PROXY_URL=<url> bash patch-kotlin-repo-proxy.sh
#
# Why: The Kotlin build declares repositories in settings.gradle and in
# included builds (e.g. repo/gradle-settings-conventions). Those use
# hardcoded cache-redirector/redirector URLs. Init script only affects
# root settings; included builds use their own repos, so requests still
# go to cache-redirector. This script replaces those URLs so all
# resolution goes through the proxy at PROXY_URL.

set -e
WORKSPACE_DIR="${WORKSPACE_DIR:?}"
PROXY_URL="${PROXY_URL:?}"

# Escape PROXY_URL for use in sed replacement (escape & and \)
PROXY_ESC="${PROXY_URL//\\/\\\\}"
PROXY_ESC="${PROXY_ESC//&/\\&}"

replace_in_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local tmp
  tmp=$(mktemp)
  sed -e "s|https://cache-redirector\.jetbrains\.com/maven-central|${PROXY_ESC}|g" \
      -e "s|https://cache-redirector\.jetbrains\.com/dl\.google\.com/dl/android/maven2|${PROXY_ESC}|g" \
      -e "s|https://redirector\.kotlinlang\.org/maven/kotlin-dependencies|${PROXY_ESC}|g" \
      -e "s|https://redirector\.kotlinlang\.org/maven/bootstrap|${PROXY_ESC}|g" \
      -e "s|https://packages\.jetbrains\.team/maven/p/ij/intellij-dependencies|${PROXY_ESC}|g" \
      "$f" > "$tmp" && mv "$tmp" "$f"
}

# Files that declare repositories (do not patch cache-redirector plugin's internal map)
replace_in_file "$WORKSPACE_DIR/settings.gradle"
replace_in_file "$WORKSPACE_DIR/repo/gradle-settings-conventions/settings.gradle.kts"
replace_in_file "$WORKSPACE_DIR/build.gradle.kts"
replace_in_file "$WORKSPACE_DIR/repo/gradle-settings-conventions/kotlin-daemon-config/build.gradle.kts"
replace_in_file "$WORKSPACE_DIR/repo/gradle-settings-conventions/kotlin-bootstrap/build.gradle.kts"
replace_in_file "$WORKSPACE_DIR/repo/gradle-settings-conventions/jvm-toolchain-provisioning/build.gradle.kts"
replace_in_file "$WORKSPACE_DIR/repo/gradle-settings-conventions/internal-gradle-setup/build.gradle.kts"
replace_in_file "$WORKSPACE_DIR/repo/gradle-settings-conventions/develocity/build.gradle.kts"

# Kotlin bootstrap repo URL in script
replace_in_file "$WORKSPACE_DIR/repo/gradle-settings-conventions/kotlin-bootstrap/src/main/kotlin/kotlin-bootstrap.settings.gradle.kts"

echo "Patched Kotlin repo to use Maven proxy: $PROXY_URL"
