#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run inside the QA bwrap only. Creates one fresh account and deletes the password file.
Prints nothing from the account response. Status file has no guid, password, or hello.
"""
import json
import subprocess
import sys
from pathlib import Path

STATUS = Path("/state/qa-account-status.json")
PASSWORD = Path("/state/account/.private/qa-password")
BRIDGE = Path("/state/account/bridge.py")


def write_status(payload):
    STATUS.write_text(json.dumps(payload, sort_keys=True) + "\n")
    STATUS.chmod(0o600)


def main():
    if not PASSWORD.is_file() or not BRIDGE.is_file():
        write_status({"ok": False, "error": "bootstrap_inputs_missing"})
        return 2
    password = PASSWORD.read_text(encoding="utf-8")
    PASSWORD.unlink()
    if password.endswith("\n"):
        password = password[:-1]
    completed = subprocess.run(
        [sys.executable, str(BRIDGE), "--base-url", "http://127.0.0.1:18080", "--timeout", "15",
         "bootstrap", "--mail-disabled", "--local-server-list", "--profile", "--password-stdin"],
        input=password + "\n", text=True, capture_output=True, timeout=30)
    password = ""
    try:
        data = json.loads(completed.stdout)
    except (json.JSONDecodeError, TypeError):
        write_status({"ok": False, "error": "unreadable_status"})
        return 2
    profile = data.get("profile_path") or ""
    name = Path(profile).name if profile else ""
    ready = bool(data.get("ok")) and name.startswith("dev-") and name.endswith(".json")
    write_status({"ok": ready, "profile_ready": ready, "profile_name": name if ready else "",
                  "error": "" if ready else str(data.get("error") or "bootstrap_failed")})
    return 0 if ready else 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.SubprocessError):
        write_status({"ok": False, "error": "bootstrap_failed"})
        sys.exit(2)
