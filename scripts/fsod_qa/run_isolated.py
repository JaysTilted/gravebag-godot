#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Isolated live QA for walking + realm entry.
Uses this worktree's bwrap state only. Never signals Jay's backend or window.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "scripts/fsod_backend/.state"
BACKEND = ROOT / "scripts/fsod_backend/backend.py"
JAY_STATE = Path("/home/jay/gravebag-godot/scripts/fsod_backend/.state")
JAY_SUPERVISOR_HINT = 2438472
GODOT = Path("/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64")


class IsolationError(RuntimeError):
    pass


def assert_qa_state(state=STATE, jay_state=JAY_STATE, root=ROOT):
    resolved = Path(state).resolve()
    jay = Path(jay_state).resolve()
    if resolved == jay or "gravebag-godot/scripts/fsod_backend/.state" in str(resolved):
        raise IsolationError("refusing Jay's live backend state")
    if not str(resolved).startswith(str(Path(root).resolve()) + "/scripts/fsod_backend/.state"):
        raise IsolationError("QA state must be this worktree backend state")
    return resolved


def proc_ns(pid):
    return os.readlink(f"/proc/{pid}/ns/net")


def proc_cmd(pid):
    return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()


def jay_snapshot():
    pid = JAY_SUPERVISOR_HINT
    try:
        cmd = proc_cmd(pid)
        ns = proc_ns(pid)
        ppid = int(next(line.split()[1] for line in Path(f"/proc/{pid}/status").read_text().splitlines() if line.startswith("PPid:")))
        parent = proc_cmd(ppid)
    except OSError:
        return {"pid": pid, "alive": False}
    alive = "supervisor.py" in cmd and "gravebag-godot/scripts/fsod_backend/.state" in parent
    return {"pid": pid, "alive": alive, "ns": ns}


def assert_jay_untouched(before):
    after = jay_snapshot()
    if before.get("alive") and not after.get("alive"):
        raise IsolationError("Jay's backend supervisor disappeared during QA")
    if before.get("alive") and before.get("ns") != after.get("ns"):
        raise IsolationError("Jay's backend network namespace changed")
    return after


def our_supervisor():
    launch = json.loads((STATE / "launch.json").read_text())
    outer = int(launch["pid"])
    cmd = proc_cmd(outer)
    if str(STATE) not in cmd or "supervisor.py" not in cmd:
        raise IsolationError("launch.json is not this worktree supervisor")
    inner = None
    parents = {outer}
    for _ in range(4):
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            pid = int(entry.name)
            try:
                status = (entry / "status").read_text()
                ppid = int(next(line.split()[1] for line in status.splitlines() if line.startswith("PPid:")))
            except (OSError, StopIteration, ValueError):
                continue
            if ppid not in parents:
                continue
            parents.add(pid)
            argv = (entry / "cmdline").read_bytes()
            if b"/state/supervisor.py" in argv and b"_supervise" in argv:
                inner = pid
    if inner is None:
        raise IsolationError("QA supervisor child not found")
    if inner == JAY_SUPERVISOR_HINT:
        raise IsolationError("QA supervisor resolved to Jay's pid")
    return {"outer_pid": outer, "inner_pid": inner, "ns": proc_ns(inner), "host_ns": proc_ns(os.getpid())}


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_head():
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()


def source_hashes():
    files = subprocess.check_output(["git", "ls-files", "src/client/fsod", "src/game", "src/net/fsod", "project.godot"], cwd=ROOT, text=True).split()
    extra = ["scripts/fsod_qa/live_driver.gd", "scripts/fsod_qa/run_isolated.py", "scripts/fsod_qa/account_bootstrap.py"]
    return {name: sha256(ROOT / name) for name in files + extra if (ROOT / name).is_file()}


def run_backend(*args, timeout=120):
    assert_qa_state()
    completed = subprocess.run(["python3", str(BACKEND), *args], cwd=ROOT, text=True, capture_output=True, timeout=timeout)
    if completed.returncode != 0:
        raise IsolationError(completed.stderr.strip() or completed.stdout.strip() or "backend command failed")
    if completed.stdout.strip().startswith("{"):
        return json.loads(completed.stdout)
    return {"text": completed.stdout.strip()}


def wait_exec(token, deadline):
    path = STATE / f"exec-{token}.json"
    while time.monotonic() < deadline:
        if path.is_file():
            data = json.loads(path.read_text())
            if "exit_code" in data or data.get("stopped"):
                return data
        time.sleep(0.5)
    raise IsolationError("exec deadline exceeded")


def launch_exec(argv, timeout):
    result = run_backend("exec", "--timeout", str(timeout), "--", *argv, timeout=30)
    if result.get("exec") != "launched":
        raise IsolationError("exec did not launch")
    return result["id"], wait_exec(result["id"], time.monotonic() + timeout + 15)


def attest_local_config():
    realm = (STATE / "source/bin/Debug/wServer.cfg").read_text()
    account = (STATE / "source/bin/Debug/server.cfg").read_text()
    if "verifyEmail:false" not in realm.replace(" ", "") or "svr0Adr:127.0.0.1" not in account.replace(" ", ""):
        raise IsolationError("generated config is not the local no-mail fixture")


def bootstrap_account():
    attest_local_config()
    account = STATE / "account"
    private = account / ".private"
    private.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(private, 0o700)
    for name in ("bridge.py", "login_profile.py", "rsa_public.py"):
        shutil.copy2(ROOT / "scripts/fsod_account" / name, account / name)
    shutil.copy2(ROOT / "scripts/fsod_qa/account_bootstrap.py", account / "account_bootstrap.py")
    password_path = private / "qa-password"
    password_path.write_text(os.urandom(18).hex() + "\n")
    os.chmod(password_path, 0o600)
    token, result = launch_exec(["python3", "/state/account/account_bootstrap.py"], 60)
    status_path = STATE / "qa-account-status.json"
    status = json.loads(status_path.read_text()) if status_path.is_file() else {"ok": False}
    if result.get("exit_code") != 0 or not status.get("ok"):
        raise IsolationError("account bootstrap failed")
    profile = private / status["profile_name"]
    if not profile.is_file() or profile.stat().st_mode & 0o077:
        raise IsolationError("QA profile is missing or not owner-only")
    return {"profile_name": profile.name, "mode": oct(profile.stat().st_mode & 0o777), "exec": token}


def stage_client():
    client = STATE / "client"
    if client.exists():
        shutil.rmtree(client)
    shutil.copytree(ROOT / "src", client / "src", ignore=shutil.ignore_patterns("__pycache__"))
    for name in ("project.godot", "src/main.gd", "src/main.gd.uid", "src/main.tscn"):
        source = ROOT / name
        if source.is_file():
            target = client / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    shutil.copy2(ROOT / "scripts/fsod_qa/live_driver.gd", client / "src/game/fsod_qa_live_driver.gd")
    if not GODOT.is_file():
        raise IsolationError("Godot binary missing")
    shutil.copy2(GODOT, STATE / "Godot")
    os.chmod(STATE / "Godot", 0o755)
    return {"driver_sha256": sha256(client / "src/game/fsod_qa_live_driver.gd"), "godot_sha256": sha256(STATE / "Godot")}


def check_isolation():
    state = assert_qa_state()
    try:
        assert_qa_state(JAY_STATE)
    except IsolationError:
        refused = True
    else:
        refused = False
    if not refused:
        raise IsolationError("Jay state was not refused")
    print(json.dumps({"ok": True, "state": str(state), "jay_refused": True}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-isolation", action="store_true")
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.check_isolation:
        check_isolation()
        return
    before = jay_snapshot()
    assert_qa_state()
    ours = our_supervisor()
    if ours["ns"] == ours["host_ns"] or (before.get("alive") and ours["ns"] == before.get("ns")):
        raise IsolationError("QA backend is not in its own network namespace")
    ready = run_backend("verify")
    if ready.get("ready") is not True:
        raise IsolationError("QA backend is not ready")
    account = bootstrap_account()
    staged = stage_client()
    head = git_head()
    hashes = source_hashes()
    import_id, imported = launch_exec(["/state/Godot", "--headless", "--path", "/state/client", "--import"], 180)
    if imported.get("exit_code") != 0:
        raise IsolationError("client import failed")
    profile = f"/state/account/.private/{account['profile_name']}"
    # NVIDIA's EGL vendor crashes Xvfb inside this user namespace. Mesa
    # software GL keeps the render offscreen and off Jay's display.
    run_id, ran = launch_exec([
        "env", "LIBGL_ALWAYS_SOFTWARE=1", "__GLX_VENDOR_LIBRARY_NAME=mesa",
        "__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json",
        "xvfb-run", "-a", "-e", "/state/qa-xvfb.err",
        "/state/Godot", "--path", "/state/client", "--resolution", "1280x720",
        "-s", "res://src/game/fsod_qa_live_driver.gd", "--",
        f"--fsod-login-file={profile}",
        "--fsod-report=/state/qa-live-report.json",
        "--fsod-frame-dir=/state/qa-frames",
        "--fsod-deadline-ms=180000",
    ], 240)
    after = assert_jay_untouched(before)
    report_path = STATE / "qa-live-report.json"
    report = json.loads(report_path.read_text()) if report_path.is_file() else {}
    summary = {
        "head": head,
        "backend_pid": ours,
        "jay": {"before": {k: before[k] for k in before if k != "cmd_has_supervisor"}, "after_alive": after.get("alive"), "after_ns": after.get("ns")},
        "account": account,
        "staged": staged,
        "import_exec": import_id,
        "run_exec": run_id,
        "run_exit": ran.get("exit_code"),
        "run_timed_out": ran.get("timed_out"),
        "source_sha256": hashes,
        "report_keys": sorted(report.keys()),
    }
    print(json.dumps({"ok": ran.get("exit_code") == 0 and not ran.get("timed_out"), "summary": summary}, sort_keys=True))
    if args.evidence:
        args.evidence.mkdir(parents=True, exist_ok=True)
        if report_path.is_file():
            shutil.copy2(report_path, args.evidence / "qa-live-report.json")
        frame_dir = STATE / "qa-frames"
        if frame_dir.is_dir():
            dest = args.evidence / "frames"
            dest.mkdir(exist_ok=True)
            for frame in frame_dir.glob("*.png"):
                shutil.copy2(frame, dest / frame.name)
        (args.evidence / "isolation.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    if ran.get("exit_code") != 0 or ran.get("timed_out"):
        raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except (IsolationError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        raise SystemExit(1)
