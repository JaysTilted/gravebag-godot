#!/usr/bin/env bash
# GRAVEBAG headless smoke: import project, run main scene 5s, expect ready + no errors.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64}"
OUT="$("$GODOT" --headless --path "$ROOT" --import 2>&1)" || { echo "$OUT" | tail -n 5; echo "SMOKE FAIL: import"; exit 1; }
OUT="$("$GODOT" --headless --path "$ROOT" --quit-after 5 2>&1)"
echo "$OUT" | tail -n 5
echo "$OUT" | grep -q "GRAVEBAG ready" || { echo "SMOKE FAIL: ready line missing"; exit 1; }
echo "$OUT" | grep -qi "script ERROR\|parse ERROR\|Failed to load" && { echo "SMOKE FAIL: script errors"; exit 1; }
echo "SMOKE PASS"
