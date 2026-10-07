#!/usr/bin/env python3
"""Open only an accepted FSoD build, as Jay, on the existing local display.
Backend remains private-loopback-only. sudo only enters its net namespace;
runuser drops back to Jay before Godot starts. No root game process.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from verify import ROOT, STATE, head, verify


def backend_process():
    launch = json.loads((STATE / 'launch.json').read_text())
    parent = int(launch['pid'])
    parents = {parent}
    # Fixed-depth read of /proc (not a liveness poll); bwrap has one helper layer.
    for _ in range(4):
        for entry in Path('/proc').iterdir():
            if not entry.name.isdigit(): continue
            try:
                status = (entry / 'status').read_text()
                ppid = int(next(line for line in status.splitlines() if line.startswith('PPid:')).split()[1])
                if ppid not in parents: continue
                parents.add(int(entry.name))
                argv = (entry / 'cmdline').read_bytes().split(b'\0')
                if argv and b'python3' in argv[0] and b'/state/supervisor.py' in argv and b'_supervise' in argv:
                    return int(entry.name)
            except (OSError, StopIteration, ValueError): pass
    raise ValueError('could not find this owned backend namespace supervisor')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--login-file', type=Path, required=True)
    args = parser.parse_args()
    try:
        verify()
        profile = args.login_file.resolve()
        private = (STATE / 'account/.private').resolve()
        if not profile.is_relative_to(private) or not profile.is_file() or profile.stat().st_mode & 0o077:
            raise ValueError('login profile must be an existing owner-only runtime profile')
        if os.getuid() != 1000 or os.environ.get('DISPLAY') != ':1':
            raise ValueError('launcher expects Jay on the existing desktop display :1')
        if not os.environ.get('XAUTHORITY'):
            raise ValueError('desktop X authority is unavailable')
        backend = json.loads(subprocess.check_output(['python3', str(ROOT / 'scripts/fsod_backend/backend.py'), 'verify'], text=True, timeout=20))
        if backend.get('ready') is not True: raise ValueError('isolated original backend is not ready')
        supervisor = backend_process()
        binary = os.environ.get('GODOT_BIN', '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64')
        log_path = STATE / 'play-window.log'
        with log_path.open('wb') as log:
            process = subprocess.Popen(['sudo', '-n', 'nsenter', '-t', str(supervisor), '-n', '--',
                'runuser', '-u', 'jay', '--', 'env', 'DISPLAY=:1', 'XAUTHORITY=' + os.environ['XAUTHORITY'], 'XDG_RUNTIME_DIR=/run/user/1000',
                binary, '--path', str(STATE / 'client'), '--resolution', '1280x720', '--',
                '--fsod-client', '--fsod-login-file=' + str(profile)], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        # The caller uses a bounded watch for PLAYING/window; never a sleep loop.
        (STATE / 'play-launch.json').write_text(json.dumps({'head': head(), 'launcher_pid': process.pid, 'log': str(log_path), 'started_at': time.time()}, indent=2) + '\n')
        print('FSOD PLAY WINDOW LAUNCHED: awaiting real CREATE_SUCCESS and window readback')
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'FSOD PLAY LAUNCH FAIL: {error}\n')


if __name__ == '__main__': main()
