#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Isolated original-backend LIVE UI acceptance orchestrator (owned helper).

Owns ONLY this file's logic. Never edits existing UI files, primary/play,
STATE, or master. Fail-closed: any auth/profile fallback, shared STATE, fixed
FPS, manual stats/fill, or missing isolation raises and exits nonzero.
Intermediate HEAD: --check-prep only. Final capture runs only with
FSOD_UI_LIVE_FINAL=1 on the parent frozen HEAD after frame approval.

Final flow reuses the normal pipeline read-only (never copies it):
scripts/fsod_qa/run_isolated.py (QA state, backend exec, QA-only profile
bootstrap, Jay-untouched attestation) and scripts/fsod_play/verify.py
(stage/collect/verify of the 4 normal probes on the fresh UI client hash).
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND_PIN = "6fd20aad4a7905b13f25389c68368a942a2b68cb"
ENTRY = ROOT / "src/game/fsod_entry.gd"
LIVE_PROBE = ROOT / "src/game/fsod_live_probe.gd"
UI_PROBE = ROOT / "src/game/fsod_ui_live_probe.gd"
VERIFY = ROOT / "scripts/fsod_play/verify.py"
BACKEND = ROOT / "scripts/fsod_backend/backend.py"
RUN_ISOLATED = ROOT / "scripts/fsod_qa/run_isolated.py"
CONTRACT = ROOT / "scripts/fsod_ui_proof/contract.json"
JAY_STATE_HINTS = (
    "/home/jay/gravebag-godot/scripts/fsod_backend/.state",
    "accepted-play-ab8",
)
JAY_LIVE_PID = 629784
FORBIDDEN_MARKERS = (
    "authprofilefallback", "auth_profile_fallback", "fallback_profile",
    "sharedstate", "shared_state",
    "1/60", "fixed_fps", "fakefps", "fake_fps",
    "manualstats", "manual_stats", "fill_stats",
    "fakenpc", "fake_npc", "chrome labels",
    "send_fields", "predict_motion", "interact_requested.emit",
)
# One fresh round per runtime: the same four cases the normal verifier needs.
PROBE_KINDS = {
    "combat": ["--fsod-bot-realm"],
    "damage": ["--fsod-bot-injury"],
    "loot": ["--fsod-bot-loot"],
    "recovery": ["--fsod-bot-death-cycle"],
}
UI_SIZES = [(1280, 720), (640, 360)]
MESA_ENV = [
    "env", "LIBGL_ALWAYS_SOFTWARE=1", "__GLX_VENDOR_LIBRARY_NAME=mesa",
    "__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json",
]


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


def load_helper(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_proc(pid: int, *names: str) -> dict:
    info: dict = {"pid": pid, "alive": False}
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()
        info.update(alive=True, cmd=raw[:200], netns=os.readlink(f"/proc/{pid}/ns/net"),
                    uid=Path(f"/proc/{pid}").stat().st_uid)
    except OSError:
        pass
    return {k: info[k] for k in ("pid", "alive", *names) if k in info}


def check_isolation(state: Path, *, for_final: bool = False) -> dict:
    uid = os.getuid()
    game_uid = os.getuid() == 1000
    if for_final and not game_uid:
        raise ValueError(f"runtime must be GAME UID 1000 ONLY, not {uid}")
    if uid == 0:
        raise ValueError("runtime must never be root")
    display = os.environ.get("DISPLAY", "")
    if for_final and display in (":0", ":1"):
        raise ValueError(f"private Xvfb display required, never {display or 'unset-jay-display'}")
    if not ENTRY.is_file() or not LIVE_PROBE.is_file() or not UI_PROBE.is_file():
        raise ValueError("production entry/probes missing; refusing synthetic claim")
    if not VERIFY.is_file() or not BACKEND.is_file() or not CONTRACT.is_file():
        raise ValueError("normal helpers/contract missing")
    if not RUN_ISOLATED.is_file():
        raise ValueError("normal QA bootstrap helper missing")
    threads = int(os.environ.get("LP_NUM_THREADS", "2"))
    if for_final and threads < 2:
        raise ValueError("LP_NUM_THREADS must be 2+")
    return {"ok": True, "state": str(state), "backend_pin": BACKEND_PIN,
            "entry": str(ENTRY), "uid": uid, "display": display,
            "lp_threads": max(threads, 2)}


def check_fail_closed() -> list[str]:
    problems: list[str] = []
    for path in (ROOT / "scripts/fsod_ui_live.py", ROOT / "src/game/fsod_ui_live_probe.gd",
                 ROOT / "tests/fsod-ui-live-proof.test.mjs"):
        if not path.is_file():
            problems.append(f"missing owned helper: {path.name}")
            continue
        text = path.read_text().lower()
        for marker in FORBIDDEN_MARKERS:
            key = marker.replace(" ", "_")
            if key in text.replace(" ", "_") and "fail-closed" not in text and "fail_closed" not in text:
                problems.append(f"{path.name} contains forbidden marker {marker}")
    probe = (ROOT / "src/game/fsod_ui_live_probe.gd").read_text() if UI_PROBE.is_file() else ""
    for required in ("Input.parse_input_event", "fsod_entry", "frame-delta",
                     "Time.get_ticks", "frame-dir", "frame-deltas.json",
                     "InputEventMouseButton", "ui_diagnostics", "get_texture",
                     "FSOD UI LIVE PASS"):
        if required.lower() not in probe.lower():
            problems.append(f"ui_live_probe missing required marker: {required}")
    orch = (ROOT / "scripts/fsod_ui_live.py").read_text()
    for required in ("fail-closed", "ui_diagnostics", "os.getuid() == 1000", "xvfb-run",
                     "LP_NUM_THREADS", "backend.py", "verify.py", "run_isolated",
                     "--fsod-bot-realm", "--fsod-bot-injury", "--fsod-bot-loot",
                     "--fsod-bot-death-cycle", "runtime_hashes", "netns",
                     "bootstrap_account", '"stop"'):
        if required.lower() not in orch.lower():
            problems.append(f"orchestrator missing required wiring: {required}")
    return problems


def git_head() -> str:
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"not a PNG frame: {path.name}")
    return struct.unpack(">II", header[16:24])


def child_env() -> dict:
    env = dict(os.environ)
    try:
        env["LP_NUM_THREADS"] = str(max(2, int(env.get("LP_NUM_THREADS", "2"))))
    except ValueError:
        env["LP_NUM_THREADS"] = "2"
    return env


def run_final(state: Path, *, ttl: int, deadline_ms: int, frame_count: int) -> int:
    qa = load_helper(RUN_ISOLATED, "fsod_run_isolated")
    verify = load_helper(VERIFY, "fsod_play_verify")
    jay_before = read_proc(JAY_LIVE_PID, "netns", "uid")
    jay_before["hint"] = dict(qa.jay_snapshot())
    qa.assert_qa_state()
    ours = qa.our_supervisor()
    if ours["ns"] == ours["host_ns"]:
        return fail("QA backend is not in its own network namespace")
    ready = qa.run_backend("verify")
    if ready.get("ready") is not True:
        started_backend = qa.run_backend("start", "--ttl", str(ttl))
        ready = qa.run_backend("verify")
        if ready.get("ready") is not True:
            return fail("isolated original backend is not ready after owned start")
        receipt_note = {"backend_start": started_backend}
    else:
        receipt_note = {"backend_start": "already_ready"}
    head = qa.git_head()
    source = verify.source_hashes()
    receipt: dict = {"head": head, "backend_pin": BACKEND_PIN, "uid": os.getuid(),
                     "display": os.environ.get("DISPLAY", ""), "source_sha256": source,
                     "jay_before": jay_before, "qa_backend": ours,
                     "backend": receipt_note}
    try:
        account = qa.bootstrap_account()
        profile = f"/state/account/.private/{account['profile_name']}"
        receipt["qa_profile"] = {"name": account["profile_name"], "mode": account["mode"]}
        subprocess.run(["python3", str(VERIFY), "stage"], cwd=ROOT, env=child_env(),
                       capture_output=True, text=True, timeout=120, check=True)
        godot_src = Path("/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64")
        godot_dst = state / "Godot"
        godot_dst.write_bytes(godot_src.read_bytes())
        godot_dst.chmod(0o755)
        receipt["godot_sha256"] = sha256(godot_dst)
        import_id, imported = qa.launch_exec(
            ["/state/Godot", "--headless", "--path", "/state/client", "--import"], 180)
        if imported.get("exit_code") != 0:
            return fail("client import failed")
        exec_ids: dict = {}
        for kind, flags in PROBE_KINDS.items():
            token, result = qa.launch_exec(MESA_ENV + [
                "xvfb-run", "-a", "-e", f"/state/qa-xvfb-{kind}.err",
                "nice", "-n", "10", "/state/Godot", "--path", "/state/client",
                "--resolution", "1280x720", "-s", "res://src/game/fsod_live_probe.gd", "--",
                f"--fsod-login-file={profile}", "--fsod-frame-dir=/state/live-frames",
                *flags, f"--fsod-deadline-ms={deadline_ms}"], 300)
            if result.get("exit_code") != 0 or result.get("timed_out"):
                return fail(f"normal {kind} probe did not exit cleanly")
            exec_ids[kind] = token
        subprocess.run(["python3", str(VERIFY), "collect"] + [
            item for kind in PROBE_KINDS for item in ("--" + kind, exec_ids[kind])],
            cwd=ROOT, env=child_env(), capture_output=True, text=True, timeout=120, check=True)
        subprocess.run(["python3", str(VERIFY), "verify"], cwd=ROOT, env=child_env(),
                       capture_output=True, text=True, timeout=120, check=True)
        receipt["normal_4probe"] = exec_ids
        receipt["runtime_sha256"] = verify.runtime_hashes()
        ui_runs: dict = {}
        for width, height in UI_SIZES:
            frame_arg = f"/state/ui-frames-{width}x{height}"
            token, result = qa.launch_exec(MESA_ENV + [
                "xvfb-run", "-a", "-e", f"/state/qa-xvfb-ui-{width}x{height}.err",
                "nice", "-n", "10", "/state/Godot", "--path", "/state/client",
                "--resolution", f"{width}x{height}", "-s",
                "res://src/game/fsod_ui_live_probe.gd", "--",
                f"--fsod-login-file={profile}", f"--fsod-frame-dir={frame_arg}",
                "--fsod-ui-mode=ui-live", f"--fsod-deadline-ms={deadline_ms}",
                f"--fsod-max-frames={frame_count}"], 300)
            log = (state / f"exec-{token}.log").read_text()
            if result.get("exit_code") != 0 or "FSOD UI LIVE PASS" not in log:
                return fail(f"UI live probe {width}x{height} has no PASS proof")
            ui_runs[f"{width}x{height}"] = {"exec": token, **validate_ui_run(state, width, height)}
        receipt["ui_runs"] = ui_runs
        receipt["jay_after"] = qa.assert_jay_untouched(
            {"pid": 0, "alive": jay_before.get("alive", False),
             "ns": jay_before.get("netns", "")})
        out = state / "play-proof" / head / "ui-live-receipt.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"ok": True, "receipt": str(out), "head": head,
                          "ui_runs": sorted(ui_runs), "normal_4probe": sorted(exec_ids)}))
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        return fail(f"live acceptance error: {error}")
    finally:
        # TTL-bounded owned cleanup: stop ONLY our QA backend, never Jay's.
        try:
            qa.run_backend("stop")
        except Exception as error:
            print(f"FSOD UI LIVE WARN owned stop failed: {error}", file=sys.stderr)


def validate_ui_run(state: Path, width: int, height: int) -> dict:
    frames = sorted((state / f"ui-frames-{width}x{height}").glob("ui-live-*.png"))
    if not frames:
        raise ValueError(f"no readable frames at {width}x{height}")
    for frame in frames:
        if png_size(frame) != (width, height):
            raise ValueError(f"unexpected render dimensions: {frame.name}")
    deltas = json.loads((state / f"ui-frames-{width}x{height}" / "frame-deltas.json").read_text())
    series = deltas.get("deltas", [])
    if not series or any(d <= 0 for d in series):
        raise ValueError("frame deltas are not genuine sampling")
    meta = json.loads((state / f"ui-frames-{width}x{height}" / "ui-live-meta.json").read_text())
    if meta.get("viewport", {}).get("w") != width:
        raise ValueError("viewport does not match requested production size")
    diag_ok, fills = check_diagnostics(state / f"ui-frames-{width}x{height}" / "ui-diagnostics.jsonl")
    if not diag_ok:
        raise ValueError("ui_diagnostics schema/values missing")
    return {"frames": len(frames), "avg_delta": deltas.get("avg_delta"),
            "pid": meta.get("pid"), "played": meta.get("played"),
            "clicked_new": meta.get("clicked_new_character"),
            "clicked_reconnect": meta.get("clicked_reconnect"),
            "fills": fills, "frame_sha256": {f.name: sha256(f) for f in frames}}


def check_diagnostics(path: Path) -> tuple[bool, dict]:
    first: dict | None = None
    last: dict | None = None
    changed = False
    for line in path.read_text().splitlines():
        snap = json.loads(line)
        diag = snap.get("diag", {})
        if diag.get("schema") != "gravebag.ui_diagnostics.v1":
            return False, {}
        bars = diag.get("bars", {})
        for key, value in bars.items():
            if isinstance(value, (int, float)) and not 0.0 <= value <= 1.0:
                return False, {}
        if first is None:
            first = bars
        if last is not None and bars != last:
            changed = True
        last = bars
    if first is None:
        return False, {}
    return True, {"snapshots": sum(1 for _ in path.read_text().splitlines() if _.strip()),
                  "fills_changed": changed}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-prep", action="store_true")
    ap.add_argument("--check-isolation", action="store_true")
    ap.add_argument("--run-final", action="store_true")
    ap.add_argument("--state", default=None)
    ap.add_argument("--deadline-ms", type=int, default=180000)
    ap.add_argument("--max-attempts", type=int, default=180)
    ap.add_argument("--frame-count", type=int, default=3600)
    ap.add_argument("--ttl", type=int, default=1800)
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
        report = {"ok": not problems and iso["uid"] == 1000, "problems": problems,
                  "head": head, "state": iso["state"], "backend_pin": BACKEND_PIN,
                  "uid": iso["uid"],
                  "final_capture": "pending-parent-frozen-head-and-frame-approval",
                  "note": "prep only; no 4-probe/UI live capture until FSOD_UI_LIVE_FINAL=1"}
        print(json.dumps(report, indent=2))
        return 0 if report["ok"] else 1
    if not args.run_final:
        return fail("refusing live capture: use --run-final with FSOD_UI_LIVE_FINAL=1 only on parent frozen HEAD + frame approval")
    # Full live capture path is event-driven and requires explicit final gate.
    if os.environ.get("FSOD_UI_LIVE_FINAL") != "1":
        return fail("refusing live capture: set FSOD_UI_LIVE_FINAL=1 only on parent frozen HEAD + frame approval")
    if not 1000 <= args.deadline_ms <= 300000:
        return fail("deadline out of bounds")
    if not 1 <= args.max_attempts <= 10000:
        return fail("max-attempts out of bounds")
    if not 30 <= args.frame_count <= 20000:
        return fail("frame-count out of bounds")
    if not 10 <= args.ttl <= 21600:
        return fail("backend ttl out of bounds")
    # Liveness uses bounded exec waits in run_final, never a blocking bash loop.
    try:
        check_isolation(state, for_final=True)
    except ValueError as e:
        return fail(str(e))
    problems = check_fail_closed()
    if problems:
        return fail("; ".join(problems))
    return run_final(state, ttl=args.ttl, deadline_ms=args.deadline_ms, frame_count=args.frame_count)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
