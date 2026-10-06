#!/usr/bin/env bash
# GRAVEBAG single acceptance gate (CCGS smoke-check analog).
# One command proves a tree: import + selftests + smoke + scripted dive + real frames.
# Usage: bash scripts/verify.sh [--fast]   (--fast skips the xvfb dive)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64}"
cd "$ROOT" || exit 1

step() { echo "--- $1 ---"; }
fail() { echo "VERIFY FAIL: $1"; exit 1; }

step "import"; "$GODOT" --headless --path . --import > /dev/null 2>&1 || fail "import"
step "selftests"; bash tests/run_all.sh > /tmp/gravebag-verify-tests.log 2>&1 || { tail -n 5 /tmp/gravebag-verify-tests.log; fail "selftests"; }
tail -n 1 /tmp/gravebag-verify-tests.log
step "smoke"; bash scripts/smoke.sh | tail -n 1 | grep -q "SMOKE PASS" || fail "smoke"

if [ "${1:-}" != "--fast" ]; then
  step "dive (real pixels)"
  command -v xvfb-run > /dev/null || fail "xvfb-run missing"
  rm -rf /tmp/gravebag-frames
  OUT="$(xvfb-run -a "$GODOT" --path . --resolution 1280x720 -- --auto-test 2>&1)"
  echo "$OUT" | grep -E "DIVE PASS" || { echo "$OUT" | tail -n 5; fail "dive"; }
  echo "$OUT" | grep -qi "ERROR" && fail "dive errors"
  N="$(find /tmp/gravebag-frames -name "*.png" -size +10k 2>/dev/null | wc -l)"
  [ "$N" -ge 6 ] || fail "frames (only $N/6 real frames)"
  echo "frames: $N/6 real"
fi
echo "VERIFY PASS"
