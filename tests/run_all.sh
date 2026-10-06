#!/usr/bin/env bash
# GRAVEBAG selftest harness: run every src/**/selftest.gd headless, aggregate PASS/FAIL.
# Usage: bash tests/run_all.sh (GODOT_BIN override allowed)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-Godot_v4.6-stable_linux.x86_64}"

mapfile -t TESTS < <(find "$ROOT/src" -name "*selftest.gd" | sort)
if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "run_all: no selftest.gd files under src/ — nothing to run"
  exit 0
fi

pass=0
fail=0
failed=()
echo "--- importing project (rebuilds class cache) ---"
"$GODOT" --headless --path "$ROOT" --import > /dev/null 2>&1 || { echo "run_all: import failed"; exit 1; }
for t in "${TESTS[@]}"; do
  echo "=== ${t} ==="
  if "$GODOT" --headless --path "$ROOT" -s "$t" 2>&1; then
    echo "PASS: ${t}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${t} (exit $?)"
    fail=$((fail + 1))
    failed+=("$t")
  fi
done

total=$((pass + fail))
echo "run_all: ${pass} passed, ${fail} failed, ${total} total"
if [ "$fail" -ne 0 ]; then
  echo "FAILURES:"
  printf ' - %s\n' "${failed[@]}"
  exit 1
fi
exit 0
