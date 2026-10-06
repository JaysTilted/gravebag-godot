#!/usr/bin/env python3
"""Build and run the pinned ORIGINAL FSoD backend in a private Linux sandbox.
No source reference edits, package downloads, existing DB, or host networking.
"""
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import re
import selectors
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import time
import urllib.request
import uuid

REVISION = "6fd20aad4a7905b13f25389c68368a942a2b68cb"
HERE = Path(__file__).resolve().parent
STATE = HERE / ".state"
DB_PORT, REALM_PORT, ACCOUNT_PORT, POLICY_PORT = 33306, 2050, 18080, 1843
PROJECTS = ("wServer/wServer.csproj", "server/server.csproj", "terrain/terrain.csproj")


def run(argv, *, timeout=120, **kwargs):
    return subprocess.run(argv, check=True, timeout=timeout, **kwargs)


def sandbox(argv, cwd="/state"):
    # No host home, /run DB sockets, external routes or DNS. Only the private
    # state tree is writable. bwrap brings up an isolated loopback interface.
    args = ["bwrap", "--unshare-all", "--new-session", "--ro-bind", "/usr", "/usr",
            "--ro-bind", "/etc", "/etc", "--dev", "/dev", "--proc", "/proc",
            "--tmpfs", "/tmp", "--tmpfs", "/run", "--dir", "/home",
            "--bind", str(STATE), "/state", "--chdir", cwd,
            "--clearenv", "--setenv", "PATH", "/usr/bin:/usr/sbin:/bin",
            "--setenv", "HOME", "/tmp", "--setenv", "TMPDIR", "/tmp",
            "--setenv", "FSOD_DB_PORT", str(DB_PORT)]
    for path in ("/lib", "/lib64", "/bin", "/sbin"):
        if Path(path).exists():
            args.extend(["--ro-bind", path, path])
    return args + argv


def require_state():
    if not (STATE / "manifest.json").is_file():
        raise RuntimeError("run build first")


def control(command):
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(12)
        conn.connect(str(STATE / "control.sock"))
        message = json.dumps(command) if isinstance(command, dict) else command
        conn.sendall((message + "\n").encode())
        body = bytearray()
        while True:
            data = conn.recv(65536)
            if not data:
                break
            body.extend(data)
            if len(body) > 1024 * 1024:
                raise RuntimeError("oversized supervisor response")
    return json.loads(body)


def build(source, dependencies):
    if (STATE / "control.sock").exists():
        raise RuntimeError("stop the owned runtime before rebuilding")
    for tool in ("git", "xbuild", "mcs", "mono", "bwrap", "mariadbd", "mariadb-install-db", "mariadb", "patch"):
        if not shutil.which(tool):
            raise RuntimeError("missing executable: " + tool)
    source = Path(source).resolve()
    revision = run(["git", "-C", str(source), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if revision != REVISION:
        raise RuntimeError("source must be pinned at " + REVISION)
    STATE.mkdir(mode=0o700, exist_ok=True)
    os.chmod(STATE, 0o700)
    checkout = STATE / "source"
    if checkout.exists():
        shutil.rmtree(checkout) # Only our ignored build snapshot, never source.
    checkout.mkdir()
    # Archive HEAD, not the operator's potentially dirty/compiled source tree.
    archive = run(["git", "-C", str(source), "archive", REVISION], capture_output=True).stdout
    roots = {"wServer", "server", "db", "DungeonGen", "terrain", "packages", "RotMG.Common.dll", "LICENSE"}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar:
            parts = Path(member.name).parts
            if not parts or parts[0] not in roots:
                continue
            if member.issym() or member.islnk() or ".." in parts or member.name.startswith("/"):
                raise RuntimeError("unsafe source archive member")
            if member.name.lower().endswith((".cfg", ".sql", "app.config", "unlockedaccounts.txt")):
                continue # No original credentials, DB rows or config copied.
            tar.extract(member, checkout, filter="data")
    # Read schema declarations ONLY; no dumped accounts/passwords/user rows.
    sql = run(["git", "-C", str(source), "show", REVISION + ":db/rotmgprod.sql"], capture_output=True).stdout.decode("utf-8-sig")
    declarations = re.findall(r"CREATE TABLE\b.*?;", sql, re.I | re.S)
    if len(declarations) != 19:
        raise RuntimeError("unexpected pinned schema table count")
    schema = "SET SESSION sql_mode='';\n" + "\n".join(declarations) + "\n"
    schema = re.sub(r"AUTO_INCREMENT=\d+", "AUTO_INCREMENT=1", schema)
    (STATE / "schema.sql").write_text(schema)
    # Infrastructure-only patch; AI/content/formulas remain original.
    dependency_lock = json.loads((HERE / "dependencies.lock.json").read_text())
    dependency_dir = checkout / ".dependencies"
    dependency_dir.mkdir()
    for entry in dependency_lock["assemblies"]:
        artifact = Path(dependencies) / entry["relative_dll"]
        if not artifact.is_file() or hashlib.sha256(artifact.read_bytes()).hexdigest() != entry["sha256"]:
            raise RuntimeError("missing/hash-mismatched dependency: " + entry["relative_dll"])
        shutil.copy2(artifact, dependency_dir / artifact.name)
    patch = HERE / "linux-isolation.patch"
    with patch.open("rb") as stream:
        run(["patch", "--batch", "--forward", "-p1"], cwd=checkout, stdin=stream, capture_output=True)
    # Project content items still require empty fixture placeholders before
    # compilation. Never restore the excluded source credential/data files.
    (checkout / "db" / "UnlockedAccounts.txt").write_text("# Empty isolated fixture\n")
    (checkout / "db" / "rotmgprod.sql").write_text("-- Fixture DDL is in /state/schema.sql\n")
    for project, config_name in (("db", "app.config"), ("wServer", "App.config"),
                                 ("server", "App.config"), ("terrain", "app.config")):
        (checkout / project / config_name).write_text(
            '<?xml version="1.0"?><configuration><startup><supportedRuntime version="v4.0" /></startup></configuration>\n')
    # All executable runtime configs are generated, never source values.
    output = checkout / "bin" / "Debug"
    output.mkdir(parents=True, exist_ok=True)
    defaults = {"db_host": "127.0.0.1", "db_database": "fsod", "db_user": "fsod", "db_auth": "",
                "verifyEmail": "false", "serverDomain": "http://127.0.0.1:18080",
                "serverEmail": "disabled@localhost.invalid", "serverEmailPassword": "",
                "smtpHost": "127.0.0.1", "smtpPort": "2525"}
    realm = defaults | {"port": str(REALM_PORT), "policyPort": str(POLICY_PORT), "maxClients": "100",
                        "tps": "20", "whiteList": "false", "whitelistTurnOff": "2000-01-01",
                        "broadcastNews": "false"}
    account = defaults | {"port": str(ACCOUNT_PORT), "testingOnline": "false", "svrNum": "1",
                          "svr0Adr": "127.0.0.1", "svr0Name": "FSoD Local", "svr0Location": "", "svr0Admin": "false",
                          "supportLink": "http://127.0.0.1:18080"}
    for name, config in (("wServer", realm), ("server", account)):
        content = "".join(k + ":" + v + "\n" for k, v in config.items())
        (checkout / name / (name + ".cfg")).write_text(content)
        (output / (name + ".cfg")).write_text(content)
        # Portable console appender; original logging layout is not gameplay.
        logging_config = (checkout / name / ("log4net_" + name + ".config")).read_text()
        logging_config = logging_config.replace("log4net.Appender.ColoredConsoleAppender", "log4net.Appender.ConsoleAppender")
        import xml.etree.ElementTree as ET
        logging_xml = ET.fromstring(logging_config)
        for appender in logging_xml.iter("appender"):
            for mapping in list(appender.findall("mapping")):
                appender.remove(mapping)
        ET.ElementTree(logging_xml).write(checkout / name / ("log4net_" + name + ".config"), encoding="utf-8", xml_declaration=True)
        shutil.copy2(checkout / name / ("log4net_" + name + ".config"), output)
    build_logs = []
    for project in PROJECTS:
        logfile = STATE / (Path(project).parent.name + "-build.log")
        with logfile.open("wb") as out:
            run(sandbox(["xbuild", "/state/source/" + project, "/p:Configuration=Debug",
                         "/p:RestorePackages=false", "/verbosity:minimal"]), stdout=out, stderr=subprocess.STDOUT)
        build_logs.append(logfile.name)
    for artifact in dependency_dir.glob("*.dll"):
        shutil.copy2(artifact, output / artifact.name)
    # Metadata files are referenced by relative data/ paths, with originals
    # copied by project build. Runtime also needs the original HTTP handlers'
    # templates; retain these privately, not imported into Godot art.
    # Canonical source App is exposed at the lowercase runtime path used by
    # original handlers; no handler names or file contents are changed.
    shutil.copytree(checkout / "server" / "App", output / "app", dirs_exist_ok=True)
    shutil.copy2(checkout / "server" / "init.txt", output)
    for name in ("account", "game", "sfx", "Picture"):
        origin = checkout / "server" / name
        if origin.exists():
            shutil.copytree(origin, output / name, dirs_exist_ok=True)
    (output / "UnlockedAccounts.txt").write_text("# Empty isolated fixture\n")
    shutil.copy2(HERE / "MetadataIds.cs", output)
    with (STATE / "metadata-ids.log").open("wb") as out:
        run(sandbox(["mcs", "-r:db.dll", "-r:log4net.dll", "-r:System.Xml.Linq", "-out:MetadataIds.exe", "MetadataIds.cs"],
                    cwd="/state/source/bin/Debug"), stdout=out, stderr=subprocess.STDOUT)
        run(sandbox(["mono", "MetadataIds.exe"], cwd="/state/source/bin/Debug"), stdout=out, stderr=subprocess.STDOUT)
    if not (output / "autoId.cfg").is_file():
        raise RuntimeError("original XmlData.Dispose did not persist autoId.cfg")
    manifest = {"source_revision": revision, "projects": list(PROJECTS), "build_logs": build_logs,
                "schema_tables": len(declarations), "patch_sha256": hashlib.sha256(patch.read_bytes()).hexdigest(),
                "network": "private-loopback-only", "db_port": DB_PORT,
                "account_port": ACCOUNT_PORT, "realm_port": REALM_PORT, "policy_port": POLICY_PORT}
    (STATE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"build": "pass", **manifest}))


def bootstrap():
    require_state()
    datadir = STATE / "mariadb"
    if (datadir / "mysql").exists():
        print(json.dumps({"bootstrap": "already_initialized"}))
        return
    datadir.mkdir(exist_ok=True)
    with (STATE / "db-bootstrap.log").open("wb") as out:
        run(sandbox(["mariadb-install-db", "--no-defaults", "--datadir=/state/mariadb",
                     "--auth-root-authentication-method=normal", "--skip-test-db",
                     "--lower-case-table-names=1"]), stdout=out, stderr=subprocess.STDOUT)
    print(json.dumps({"bootstrap": "pass", "existing_database_access": False}))


def start(ttl):
    require_state()
    if not (STATE / "mariadb" / "mysql").is_dir():
        raise RuntimeError("run bootstrap first")
    if (STATE / "control.sock").exists():
        # Never silently overwrite another potentially live owned process.
        raise RuntimeError("control socket exists: verify or stop first")
    shutil.copy2(HERE / "backend.py", STATE / "supervisor.py")
    (STATE / "ready-hint").unlink(missing_ok=True)
    for name in ("database.log", "server-runtime.log", "wServer-runtime.log", "account-probe.log", "schema-import.log"):
        (STATE / name).unlink(missing_ok=True)
    log = (STATE / "supervisor.log").open("wb")
    proc = subprocess.Popen(sandbox(["python3", "/state/supervisor.py", "_supervise", "--ttl", str(ttl)]),
                            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    log.close()
    (STATE / "launch.json").write_text(json.dumps({"pid": proc.pid, "started_at": time.time(), "ttl_seconds": ttl}))
    print(json.dumps({"start": "launched", "pid": proc.pid, "deadline_seconds": ttl,
                      "next": "verify (single probe); use a bounded watcher for readiness"}))


def probe(children):
    result = {"ready": False, "alive": {name: proc.poll() is None for name, proc in children.items()},
              "network": "private-loopback-only", "ports": [DB_PORT, REALM_PORT, ACCOUNT_PORT, POLICY_PORT]}
    try:
        for port in (DB_PORT, REALM_PORT, ACCOUNT_PORT):
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                pass
        with socket.create_connection(("127.0.0.1", POLICY_PORT), timeout=1) as policy:
            policy.sendall(b"<policy-file-request/>\x00")
            result["policy_response"] = b"cross-domain-policy" in policy.recv(4096)
        endpoint = "http://127.0.0.1:18080/char/list?guid=fsod-fixture%40gmail.invalid&password=local-only"
        with urllib.request.urlopen(endpoint, timeout=5) as response:
            payload = response.read(1024 * 1024)
        if payload.startswith(b"<Error>"):
            # Exercise ORIGINAL registration, defaults, account reads and DB
            # queries. Synthetic fixture only; verifyEmail=false and no routes.
            registration = "http://127.0.0.1:18080/account/register?ignore=1&entrytag=&isAgeVerified=1&newGUID=fsod-fixture%40gmail.invalid&newPassword=local-only&guid=guest-fixture"
            with urllib.request.urlopen(registration, timeout=5) as response:
                response.read(1024 * 1024)
            with urllib.request.urlopen(endpoint, timeout=5) as response:
                payload = response.read(1024 * 1024)
        import xml.etree.ElementTree as ET
        root = ET.fromstring(payload)
        result["account_response_is_chars"] = root.tag == "Chars" and root.find("Account/AccountId") is not None
        result["account_response_bytes"] = len(payload)
        if not result["account_response_is_chars"]:
            # Original exception response is retained only in the isolated log.
            Path("/state/account-probe.log").write_bytes(payload)
        sql = run(["mariadb", "--no-defaults", "--protocol=socket", "--socket=/state/mysql.sock", "--user=root",
                   "--batch", "--skip-column-names", "--execute=SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='fsod'"],
                  capture_output=True, timeout=5)
        result["schema_tables"] = int(sql.stdout.strip())
        result["original_realm_initialized"] = Path("/state/ready-hint").is_file()
        result["ready"] = all(result["alive"].values()) and result["account_response_is_chars"] and result["schema_tables"] == 19 and result["policy_response"] and result["original_realm_initialized"]
    except Exception as error:
        result["error"] = type(error).__name__ # No raw URL/auth/query output.
    return result


def supervise(ttl):
    """Event-driven readiness. No sleeps or polling loop; capped log events and
    startup wall time, plus hard runtime lifetime. Own children only.
    """
    state = Path("/state")
    os.umask(0o077)
    selector = selectors.DefaultSelector()
    children, masters, logs = {}, [], []
    callers = {}
    control_path = state / "control.sock"
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(control_path))
    listener.listen(4)
    listener.setblocking(False)
    selector.register(listener, selectors.EVENT_READ, "control")
    stop = False
    signal.signal(signal.SIGTERM, lambda _s, _f: (_ for _ in ()).throw(InterruptedError("stop")))
    started = time.monotonic()
    deadline = started + ttl
    startup_deadline = started + 90
    events = 0
    db_ready = False
    try:
        db = subprocess.Popen(["mariadbd", "--no-defaults", "--datadir=/state/mariadb", "--socket=/state/mysql.sock",
                               "--pid-file=/state/mysql.pid", "--port=33306", "--bind-address=127.0.0.1",
                               "--skip-name-resolve", "--sql-mode=", "--lower-case-table-names=1",
                               "--innodb-buffer-pool-size=32M", "--skip-log-bin"],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        children["database"] = db
        selector.register(db.stdout, selectors.EVENT_READ, "database")
        db_log = (state / "database.log").open("ab", buffering=0)
        logs.append(db_log)
        while not stop:
            now = time.monotonic()
            if now >= deadline:
                raise TimeoutError("runtime TTL reached")
            if not db_ready and (now >= startup_deadline or events >= 10000):
                raise TimeoutError("database readiness deadline/event cap")
            for key, _mask in selector.select(timeout=min(1 if db_ready else startup_deadline - now, deadline - now)):
                if key.data == "control":
                    conn, _ = listener.accept()
                    with conn:
                        conn.settimeout(2)
                        request = conn.recv(16384).decode().strip()
                        message = json.loads(request) if request.startswith("{") else {"command": request}
                        command = message.get("command")
                        if command == "exec":
                            argv = message.get("argv", [])
                            limit = message.get("timeout", 120)
                            if not db_ready or len(callers) >= 4 or not isinstance(limit, int) or not 1 <= limit <= 600 or not 1 <= len(argv) <= 64 or any(not isinstance(arg, str) or not arg or len(arg) > 1000 or "\x00" in arg for arg in argv):
                                conn.sendall(b'{"error":"invalid_or_unready_exec"}')
                                continue
                            token = uuid.uuid4().hex
                            logfile = state / ("exec-" + token + ".log")
                            try:
                                with logfile.open("wb") as out:
                                    caller = subprocess.Popen(argv, cwd="/state", stdin=subprocess.DEVNULL,
                                                              stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
                            except OSError:
                                conn.sendall(b'{"error":"cannot_launch_exec"}')
                                continue
                            callers[token] = {"process": caller, "deadline": min(time.monotonic() + limit, deadline), "log": str(logfile)}
                            conn.sendall(json.dumps({"exec": "launched", "id": token, "timeout_seconds": limit,
                                                     "log": str(logfile), "result": "/state/exec-" + token + ".json"}).encode())
                        elif command == "stop":
                            conn.sendall(b'{"stop":"accepted"}')
                            stop = True
                        elif command == "verify":
                            response = probe(children) if db_ready else {"ready": False, "phase": "database_startup"}
                            conn.sendall(json.dumps(response).encode())
                        else:
                            conn.sendall(b'{"error":"unknown_control_command"}')
                elif key.data == "database":
                    data = os.read(key.fileobj.fileno(), 65536)
                    events += 1
                    if not data:
                        raise RuntimeError("owned MariaDB exited before shutdown")
                    db_log.write(data)
                    if not db_ready and b"ready for connections" in data:
                        admin = "CREATE DATABASE IF NOT EXISTS fsod; CREATE USER IF NOT EXISTS 'fsod'@'127.0.0.1' IDENTIFIED BY ''; GRANT ALL ON fsod.* TO 'fsod'@'127.0.0.1'; USE fsod;\n"
                        sql = (admin + (state / "schema.sql").read_text()).encode()
                        with (state / "schema-import.log").open("wb") as out:
                            run(["mariadb", "--no-defaults", "--protocol=socket", "--socket=/state/mysql.sock", "--user=root"],
                                input=sql, stdout=out, stderr=subprocess.STDOUT, timeout=30)
                        for name in ("server", "wServer"):
                            master, slave = pty.openpty()
                            masters.append(master)
                            child = subprocess.Popen(["mono", name + ".exe"], cwd="/state/source/bin/Debug",
                                                     stdin=slave, stdout=slave, stderr=slave)
                            os.close(slave)
                            children[name] = child
                            logfile = (state / (name + "-runtime.log")).open("ab", buffering=0)
                            logs.append(logfile)
                            selector.register(master, selectors.EVENT_READ, logfile)
                        db_ready = True
                        print("original account+realm processes launched; database port=33306; private network", flush=True)
                else:
                    try:
                        data = os.read(key.fileobj, 65536)
                    except OSError:
                        data = b""
                    if not data:
                        selector.unregister(key.fileobj)
                    else:
                        key.data.write(data)
                        if b"Game World initalized." in data:
                            (state / "ready-hint").write_text("original realm map, setpieces, Oryx and population initialized\n")
                        # Mono Console requests cursor position when initializing
                        # a PTY. Answer the terminal protocol, not a gameplay key.
                        if b"\x1b[6n" in data:
                            os.write(key.fileobj, b"\x1b[1;1R")
            for token, caller in list(callers.items()):
                proc = caller["process"]
                timed_out = time.monotonic() >= caller["deadline"]
                if timed_out and proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGTERM)
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                        proc.wait(timeout=5)
                if proc.poll() is not None:
                    # Clean helper descendants (e.g. xvfb) in the owned group.
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(proc.pid, signal.SIGTERM)
                    (state / ("exec-" + token + ".json")).write_text(json.dumps({"exit_code": proc.returncode, "timed_out": timed_out, "log": caller["log"]}))
                    del callers[token]
            if db_ready and any(proc.poll() is not None for proc in children.values()):
                raise RuntimeError("original backend process exited: inspect private runtime logs")
    except InterruptedError:
        print("owned runtime stopping", flush=True)
    finally:
        for token, caller in callers.items():
            proc = caller["process"]
            if proc.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)
            (state / ("exec-" + token + ".json")).write_text(json.dumps({"exit_code": proc.returncode, "stopped": True, "log": caller["log"]}))
        for proc in reversed(list(children.values())):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)
        for master in masters:
            os.close(master)
        for logfile in logs:
            logfile.close()
        selector.close()
        listener.close()
        control_path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "bootstrap", "start", "stop", "verify", "exec", "_supervise"))
    parser.add_argument("--source", default=str(HERE.parent.parent / "references" / "fsod"))
    parser.add_argument("--dependencies", default=str(Path.home() / ".nuget" / "packages"))
    parser.add_argument("--ttl", type=int, default=1800)
    parser.add_argument("--timeout", type=int, default=120)
    args, remaining = parser.parse_known_args()
    if remaining and args.command != "exec":
        parser.error("unexpected arguments")
    if not 10 <= args.ttl <= 21600:
        parser.error("--ttl must be 10..21600 seconds")
    if args.command == "build":
        build(args.source, args.dependencies)
    elif args.command == "bootstrap":
        bootstrap()
    elif args.command == "start":
        start(args.ttl)
    elif args.command == "exec":
        argv = remaining[1:] if remaining[:1] == ["--"] else remaining
        result = control({"command": "exec", "argv": argv, "timeout": args.timeout})
        print(json.dumps(result))
        return 0 if result.get("exec") == "launched" else 1
    elif args.command == "stop":
        print(json.dumps(control("stop")))
    elif args.command == "verify":
        result = control("verify")
        print(json.dumps(result))
        return 0 if result.get("ready") else 1
    else:
        supervise(args.ttl)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print("FSOD BACKEND FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
