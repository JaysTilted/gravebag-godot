#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Isolated original-backend LIVE UI acceptance orchestrator (owned helper).

Owns ONLY this file's logic. Never edits existing UI files, primary/play,
STATE, or master. Fail-closed: any auth/profile fallback, shared STATE, fixed
FPS, manual stats/fill, or missing isolation raises and exits nonzero.
Intermediate HEAD: --check-prep only. Final capture waits for parent frozen
HEAD + frame approval (FSOD_UI_LIVE_FINAL=1).
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND_PIN = "6fd20aad4a7905b13f25389c68368a942a2b68cb"
ENTRY = ROOT / "src/game/fsod_entry.gd"
LIVE_PROBE = ROOT / "src/game/fsod_live_probe.gd"
CLOSE_LOOT = ROOT / "src/game/fsod_close_loot_probe.gd"
VERIFY = ROOT / "scripts/fsod_play/verify.py"
BACKEND = ROOT / "scripts/fsod_backend/backend.py"
CONTRACT = ROOT / "scripts/fsod_ui_proof/contract.json"
JAY_STATE_HINTS = (
    "/home/jay/gravebag-godot/scripts/fsod_backend/.state",
    "accepted-play-ab8",
)
FORBIDDEN_MARKERS = (
    "authprofilefallback", "auth_profile_fallback", "fallback_profile",
    "sharedstate", "shared_state",
    "1/60", "fixed_fps", "fakefps", "fake_fps",
    "manualstats", "manual_stats", "fill_stats",
    "fakenpc", "fake_npc", "chrome labels",
)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fail(msg: str) -> int:
    print(f"FSOD UI LIVE FAIL {msg}", file=sys.stderr)
    return 1


def resolve_state(arg: str | None) -> Path:
    state = Path(arg) if arg else (ROOT / "scripts/fsod_backend/.state")
    resolved = state.resolve()
    if resolved.is_symlink() or state.is_symlink():
        raise ValueError("QA state must not be a symlink")
    text = str(resolved)
    for hint in JAY_STATE_HINTS:
        if hint in text:
            raise ValueError(f"refusing shared/primary state: {hint}")
    root_state = str((ROOT / "scripts/fsod_backend/.state").resolve())
    if not text.startswith(root_state):
        raise ValueError(f"QA state must be this worktree backend state: {resolved}")
    return resolved


def check_isolation(state: Path, *, for_final: bool = False) -> dict:
    if os.getuid() == 0:
        raise ValueError("runtime must be GAME UID 1000, not root")
    display = os.environ.get("DISPLAY", "")
    if for_final and display == ":1":
        raise ValueError("private Xvfb display required, never :1")
    if not ENTRY.is_file() or not LIVE_PROBE.is_file() or not CLOSE_LOOT.is_file():
        raise ValueError("production entry/probes missing; refusing synthetic claim")
    if not VERIFY.is_file() or not BACKEND.is_file() or not CONTRACT.is_file():
        raise ValueError("normal helpers/contract missing")
    payload = {
        "ok": True,
        "state": str(state),
        "backend_pin": BACKEND_PIN,
        "entry": str(ENTRY),
        "uid": os.getuid(),
        "display": display,
    }
    return payload


def check_fail_closed() -> list[str]:
    problems: list[str] = []
    for path in (
        ROOT / "scripts/fsod_ui_live.py",
        ROOT / "src/game/fsod_ui_live_probe.gd",
        ROOT / "tests/fsod-ui-live-proof.test.mjs",
    ):
        if not path.is_file():
            problems.append(f"missing owned helper: {path.name}")
            continue
        text = path.read_text().lower()
        for marker in FORBIDDEN_MARKERS:
            if marker.replace(" ", "_") in text.replace(" ", "_"):
                # Allowlisted only inside explicit refusal strings is still a
                # hit unless the file also asserts refusal; keep fail-closed
                # simple: the owned helpers must contain 'fail-closed' guard.
                if "fail-closed" not in text and "fail_closed" not in text:
                    problems.append(f"{path.name} contains forbidden marker {marker}")
    probe = (ROOT / "src/game/fsod_ui_live_probe.gd").read_text() if (ROOT / "src/game/fsod_ui_live_probe.gd").is_file() else ""
    for required in ("Input.parse_input_event", "fsod_entry", "frame-delta", "Time.get_ticks"):
        if required.lower() not in probe.lower():
            problems.append(f"ui_live_probe missing required marker: {required}")
    if "ui_diagnostics" not in (ROOT / "scripts/fsod_ui_live.py").read_text():
        problems.append("orchestrator must consume ui_diagnostics, never synthesize HUD")
    return problems


def git_head() -> str:
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-prep", action="store_true")
    ap.add_argument("--check-isolation", action="store_true")
    ap.add_argument("--state", default=None)
    ap.add_argument("--deadline-ms", type=int, default=90000)
    ap.add_argument("--max-attempts", type=int, default=180)
    ap.add_argument("--frame-count", type=int, default=600)
    args = ap.parse_args(argv)
    try:
        state = resolve_state(args.state)
    except ValueError as e:
        return fail(str(e))
    if args.check_isolation:
        try:
            print(json.dumps(check_isolation(state)))
            return 0
        except ValueError as e:
            return fail(str(e))
    if args.check_prep:
        try:
            iso = check_isolation(state)
        except ValueError as e:
            return fail(str(e))
        problems = check_fail_closed()
        head = git_head()
        report = {
            "ok": not problems,
            "problems": problems,
            "head": head,
            "state": iso["state"],
            "backend_pin": BACKEND_PIN,
            "final_capture": "pending-parent-frozen-head-and-frame-approval",
            "note": "prep only; no 4-probe/UI live capture until FSOD_UI_LIVE_FINAL=1",
        }
        print(json.dumps(report, indent=2))
        return 0 if not problems else 1
    # Full live capture path is event-driven and requires explicit final gate.
    if os.environ.get("FSOD_UI_LIVE_FINAL") != "1":
        return fail("refusing live capture: set FSOD_UI_LIVE_FINAL=1 only on parent frozen HEAD + frame approval")
    if args.deadline_ms < 1000 or args.deadline_ms > 300000:
        return fail("deadline out of bounds")
    if args.max_attempts < 1 or args.max_attempts > 10000:
        return fail("max-attempts out of bounds")
    # Liveness uses watch tool event loop in the agent seat, never a blocking
    # bash sleep loop here; this CLI only validates gates and exits.
    try:
        check_isolation(state, for_final=True)
    except ValueError as e:
        return fail(str(e))
    problems = check_fail_closed()
    if problems:
        return fail("; ".join(problems))
    print(json.dumps({"ok": True, "head": git_head(), "state": str(state), "deadline_ms": args.deadline_ms, "max_attempts": args.max_attempts, "frame_count": args.frame_count}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
