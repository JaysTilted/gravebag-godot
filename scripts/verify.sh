#!/usr/bin/env bash
# GRAVEBAG single acceptance gate (CCGS smoke-check analog).
# One command proves a tree: import + selftests + smoke + scripted dive + real frames.
# Usage: bash scripts/verify.sh [--fast]   (--fast skips the xvfb dive)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64}"
cd "$ROOT" || exit 1
# Each checkout owns its logs/frames; parallel builders must not overwrite proof.
VERIFY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gravebag-verify.XXXXXX")" || exit 1
trap 'rm -rf "$VERIFY_TMP"' EXIT

step() { echo "--- $1 ---"; }
fail() { echo "VERIFY FAIL: $1"; exit 1; }

step "import"; "$GODOT" --headless --path . --import > /dev/null 2>&1 || fail "import"
step "selftests"; bash tests/run_all.sh > "$VERIFY_TMP/tests.log" 2>&1 || { tail -n 15 "$VERIFY_TMP/tests.log"; fail "selftests"; }
tail -n 1 "$VERIFY_TMP/tests.log"
step "smoke"; bash scripts/smoke.sh | tail -n 1 | grep -q "SMOKE PASS" || fail "smoke"

if [ "${1:-}" != "--fast" ]; then
  step "dive (real pixels)"
  command -v xvfb-run > /dev/null || fail "xvfb-run missing"
  OUT="$(GRAVEBAG_FRAME_DIR="$VERIFY_TMP/frames" timeout 120s xvfb-run -a "$GODOT" --path . --resolution 1280x720 -- --auto-test 2>&1)" || { echo "$OUT" | tail -n 15; fail "dive exit/timeout"; }
  echo "$OUT" | grep -E "DIVE PASS" || { echo "$OUT" | tail -n 5; fail "dive"; }
  echo "$OUT" | grep -qi "ERROR" && fail "dive errors"
  N="$(find "$VERIFY_TMP/frames" -name "*.png" -size +10k 2>/dev/null | wc -l)"
  [ "$N" -ge 6 ] || fail "frames (only $N/6 real frames)"
  echo "frames: $N/6 real"
  # Keep successful captures under this checkout for visual review.
  mkdir -p "$ROOT/reports/verify-frames"
  cp "$VERIFY_TMP/frames/"*.png "$ROOT/reports/verify-frames/"
fi
echo "VERIFY PASS"
