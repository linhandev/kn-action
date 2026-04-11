#!/usr/bin/env bash
# Serial hdc smoke (GHA hdc-ohos-verify matrix max-parallel:1). macOS ARM llvm runner.
set -euo pipefail
: "${CI_PROJECT_DIR:?}"
: "${CI_PIPELINE_ID:?}"

HDC_BIN="$(command -v hdc || true)"
if [ -z "$HDC_BIN" ] || [ ! -x "$HDC_BIN" ]; then
  echo "hdc not on PATH; skipping device verification (configure runner per AGENTS.md)."
  exit 0
fi

ROOT="${CI_PROJECT_DIR}/hdc-verify"
rm -rf "$ROOT"
mkdir -p "$ROOT/dl"

verify_one() {
  local SUF="$1"
  local SUB="$2"
  local NAME="test-binaries-ohos-${SUF}-${CI_PIPELINE_ID}.tar.gz"
  "$CI_PROJECT_DIR/scripts/ci/download-artifact-local.sh" --name="$NAME" --dir="$ROOT/dl"
  mkdir -p "$ROOT/run/$SUB"
  tar -xzf "$ROOT/dl/$NAME" -C "$ROOT/run/$SUB"

  local T=()
  local line
  while IFS= read -r line; do
    T+=("$line")
  done < <("$HDC_BIN" list targets 2>/dev/null | sed '/^[[:space:]]*$/d')
  local n="${#T[@]}"
  if [ "$n" -lt 1 ]; then
    echo "No hdc targets (connect a device)."
    "$HDC_BIN" list targets || true
    exit 1
  fi
  local TARGET="${T[0]}"
  TARGET="${TARGET%%$'\t'*}"
  TARGET="$(echo "$TARGET" | tr -d '\r')"
  export HDC_TARGET="$TARGET"
  echo "hdc target ($SUF): $TARGET"

  HDC_T() { "$HDC_BIN" -t "$HDC_TARGET" "$@"; }
  local REMOTE_BASE="/data/local/tmp/llvm-ci-${CI_PIPELINE_ID}"
  HDC_T shell mkdir -p "$REMOTE_BASE"

  local kind stem exp RDIR b RPATH OUT
  for kind in c cpp; do
    if [ "$kind" = c ]; then stem=hello_ohos_c; exp="ok_ohos_c_${SUF}"; else stem=hello_ohos_cpp; exp="ok_ohos_cpp_${SUF}"; fi
    RDIR="$ROOT/run/$SUB"
    b=""
    if [ -f "$RDIR/$stem" ]; then b="$stem"
    elif [ -f "$RDIR/${stem}.exe" ]; then b="${stem}.exe"
    else echo "Missing $stem under $RDIR"; ls -la "$RDIR"; exit 1
    fi
    RPATH="$REMOTE_BASE/${SUF}_${kind}"
    HDC_T file send "$RDIR/$b" "$RPATH"
    HDC_T shell chmod 755 "$RPATH"
    OUT=$(HDC_T shell "LD_PRELOAD=/data/app/el1/bundle/public/com.huawei.hmos.location/libs/arm64/libc++_shared.so $RPATH" 2>&1) || true
    echo "output ($SUF $kind): $OUT"
    echo "$OUT" | grep -q "$exp" || {
      echo "Expected '$exp' in output"
      exit 1
    }
  done
}

while read -r suf sub; do
  verify_one "$suf" "$sub"
done <<'EOF'
Linux_X64 linux
Windows_X64 win
macOS_ARM64 arm64
macOS_X64 x64
EOF

echo "OHOS hdc smoke checks passed for all host suffixes."
